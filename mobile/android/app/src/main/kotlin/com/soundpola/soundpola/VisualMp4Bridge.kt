package com.soundpola.soundpola

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Encodes a sorted JPEG frame sequence into an H.264 MP4 for cloud upload.
 *
 * MethodChannel: soundpola/visual_mp4
 *  - encodeJpegDir({ framesDir, outputPath, fps, width, height })
 */
class VisualMp4Bridge(
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "encodeJpegDir" -> {
                val framesDir = call.argument<String>("framesDir")
                val outputPath = call.argument<String>("outputPath")
                val fps = (call.argument<Number>("fps") ?: 12).toInt().coerceIn(1, 30)
                val width = (call.argument<Number>("width") ?: 512).toInt()
                val height = (call.argument<Number>("height") ?: 512).toInt()
                if (framesDir.isNullOrBlank() || outputPath.isNullOrBlank()) {
                    result.error("BAD_ARGS", "framesDir and outputPath are required", null)
                    return
                }
                executor.execute {
                    try {
                        encodeJpegDir(
                            framesDir = File(framesDir),
                            outputPath = outputPath,
                            fps = fps,
                            width = even(width),
                            height = even(height),
                        )
                        main.post { result.success(outputPath) }
                    } catch (error: Throwable) {
                        main.post {
                            result.error(
                                "ENCODE_FAILED",
                                error.message ?: error::class.java.simpleName,
                                null,
                            )
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    companion object {
        private const val CHANNEL = "soundpola/visual_mp4"
        private const val MIME = "video/avc"
        private const val BIT_RATE = 1_200_000
        private const val I_FRAME_INTERVAL = 2

        private fun even(v: Int): Int = if (v % 2 == 0) v else v + 1

        fun encodeJpegDir(
            framesDir: File,
            outputPath: String,
            fps: Int,
            width: Int,
            height: Int,
        ) {
            val frames = framesDir.listFiles { f ->
                f.isFile && f.name.lowercase().endsWith(".jpg")
            }?.sortedBy { it.name } ?: emptyList()
            if (frames.isEmpty()) {
                throw IllegalStateException("No JPEG frames in $framesDir")
            }

            val outFile = File(outputPath)
            outFile.parentFile?.mkdirs()
            if (outFile.exists()) outFile.delete()

            val format = MediaFormat.createVideoFormat(MIME, width, height).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar,
                )
                setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
                setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL)
            }

            val encoder = MediaCodec.createEncoderByType(MIME)
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()

            val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            var trackIndex = -1
            var muxerStarted = false
            val bufferInfo = MediaCodec.BufferInfo()
            val frameDurationUs = 1_000_000L / fps
            var inputIndex = 0
            var inputDone = false
            var outputDone = false

            try {
                while (!outputDone) {
                    if (!inputDone) {
                        val inIndex = encoder.dequeueInputBuffer(10_000)
                        if (inIndex >= 0) {
                            if (inputIndex >= frames.size) {
                                encoder.queueInputBuffer(
                                    inIndex,
                                    0,
                                    0,
                                    frameDurationUs * frames.size,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                )
                                inputDone = true
                            } else {
                                val yuv = jpegToNv21(frames[inputIndex], width, height)
                                val input = encoder.getInputBuffer(inIndex)
                                    ?: throw IllegalStateException("null input buffer")
                                input.clear()
                                input.put(yuv)
                                val pts = frameDurationUs * inputIndex
                                encoder.queueInputBuffer(inIndex, 0, yuv.size, pts, 0)
                                inputIndex += 1
                            }
                        }
                    }

                    val outIndex = encoder.dequeueOutputBuffer(bufferInfo, 10_000)
                    when {
                        outIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                        outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            if (muxerStarted) {
                                throw IllegalStateException("format changed twice")
                            }
                            trackIndex = muxer.addTrack(encoder.outputFormat)
                            muxer.start()
                            muxerStarted = true
                        }
                        outIndex >= 0 -> {
                            val encoded = encoder.getOutputBuffer(outIndex)
                                ?: throw IllegalStateException("null output buffer")
                            if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                                bufferInfo.size = 0
                            }
                            if (bufferInfo.size > 0 && muxerStarted) {
                                encoded.position(bufferInfo.offset)
                                encoded.limit(bufferInfo.offset + bufferInfo.size)
                                muxer.writeSampleData(trackIndex, encoded, bufferInfo)
                            }
                            val eos =
                                bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            encoder.releaseOutputBuffer(outIndex, false)
                            if (eos) outputDone = true
                        }
                    }
                }
            } finally {
                runCatching { encoder.stop() }
                runCatching { encoder.release() }
                if (muxerStarted) runCatching { muxer.stop() }
                runCatching { muxer.release() }
            }

            if (!outFile.exists() || outFile.length() <= 0L) {
                throw IllegalStateException("MP4 encode produced empty file")
            }
        }

        /** Decode JPEG → scale → NV12 (YUV420 semi-planar). */
        private fun jpegToNv21(file: File, width: Int, height: Int): ByteArray {
            val raw = BitmapFactory.decodeFile(file.absolutePath)
                ?: throw IllegalStateException("Failed to decode ${file.name}")
            val bitmap = if (raw.width == width && raw.height == height) {
                raw
            } else {
                val scaled = Bitmap.createScaledBitmap(raw, width, height, true)
                if (scaled !== raw) raw.recycle()
                scaled
            }
            try {
                return argbToNv21(bitmap)
            } finally {
                bitmap.recycle()
            }
        }

        private fun argbToNv21(bitmap: Bitmap): ByteArray {
            val width = bitmap.width
            val height = bitmap.height
            val argb = IntArray(width * height)
            bitmap.getPixels(argb, 0, width, 0, 0, width, height)
            val yuv = ByteArray(width * height * 3 / 2)
            var yIndex = 0
            var uvIndex = width * height
            var index = 0
            for (j in 0 until height) {
                for (i in 0 until width) {
                    val c = argb[index++]
                    val r = (c shr 16) and 0xff
                    val g = (c shr 8) and 0xff
                    val b = c and 0xff
                    val y = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                    yuv[yIndex++] = y.coerceIn(0, 255).toByte()
                    if (j % 2 == 0 && i % 2 == 0) {
                        val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                        val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                        // NV12: U then V
                        yuv[uvIndex++] = u.coerceIn(0, 255).toByte()
                        yuv[uvIndex++] = v.coerceIn(0, 255).toByte()
                    }
                }
            }
            return yuv
        }
    }
}
