package com.soundpola.soundpola

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

private const val CHANNEL = "soundpola/ring_sound"
private const val DEFAULT_ADDRESS = "CB:AF:A4:D0:6B:A5"
private const val HEADER_MAGIC = 0x3F
private const val PROTOCOL_VERSION = 4
private const val COMMAND_SYSTEM_INFO_REQ = 0x0101
private const val COMMAND_SYSTEM_INFO_RESP = 0x0102
private const val COMMAND_AUDIO_COUNT_REQ = 0x0501
private const val COMMAND_AUDIO_COUNT_RESP = 0x0502
private const val COMMAND_AUDIO_FILE_INFO_RESP = 0x0504
private const val COMMAND_AUDIO_DATA_FRAME = 0x0505
private const val COMMAND_AUDIO_NEXT_FRAME = 0x0506
private const val COMMAND_AUDIO_START_EXTRACT_QUICK = 0x0509

class RingSoundBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val channel = MethodChannel(messenger, CHANNEL)
    @Volatile private var active: RingBleSession? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connectRing" -> connectRing(call, result)
            "receiveNextRecording" -> receiveNextRecording(call, result)
            "cancel" -> {
                active?.close()
                active = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun connectRing(call: MethodCall, result: MethodChannel.Result) {
        if (active != null) {
            result.error("RING_BUSY", "Ring listener is already active.", null)
            return
        }
        val address = call.argument<String>("address") ?: DEFAULT_ADDRESS
        val scanTimeoutMs = (call.argument<Number>("scanTimeoutMs") ?: 25_000).toLong()
        val commandTimeoutMs = (call.argument<Number>("commandTimeoutMs") ?: 10_000).toLong()

        executor.execute {
            val session = RingBleSession(context, address)
            active = session
            try {
                val info = session.connectAndReadInfo(
                    scanTimeoutMs = scanTimeoutMs,
                    commandTimeoutMs = commandTimeoutMs,
                )
                main.post { result.success(info) }
            } catch (error: Throwable) {
                main.post {
                    result.error(
                        "RING_CONNECT_FAILED",
                        error.message ?: error::class.java.simpleName,
                        null,
                    )
                }
            } finally {
                session.close()
                if (active === session) active = null
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        active?.close()
        active = null
        executor.shutdownNow()
    }

    private fun receiveNextRecording(call: MethodCall, result: MethodChannel.Result) {
        if (active != null) {
            result.error("RING_BUSY", "Ring listener is already active.", null)
            return
        }
        val address = call.argument<String>("address") ?: DEFAULT_ADDRESS
        val scanTimeoutMs = (call.argument<Number>("scanTimeoutMs") ?: 120_000).toLong()
        val waitTimeoutMs = (call.argument<Number>("waitTimeoutMs") ?: 900_000).toLong()
        val commandTimeoutMs = (call.argument<Number>("commandTimeoutMs") ?: 25_000).toLong()

        executor.execute {
            val session = RingBleSession(context, address)
            active = session
            try {
                val capture = session.receiveNextRecording(
                    scanTimeoutMs = scanTimeoutMs,
                    waitTimeoutMs = waitTimeoutMs,
                    commandTimeoutMs = commandTimeoutMs,
                )
                main.post { result.success(capture) }
            } catch (error: Throwable) {
                main.post {
                    result.error(
                        "RING_RECORDING_FAILED",
                        error.message ?: error::class.java.simpleName,
                        null,
                    )
                }
            } finally {
                session.close()
                if (active === session) active = null
            }
        }
    }
}

@SuppressLint("MissingPermission")
private class RingBleSession(
    private val context: Context,
    private val address: String,
) {
    private val serviceUuid = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
    private val txUuid = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e")
    private val rxUuid = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    private val cccUuid = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    private val dispatcher = PacketDispatcher()
    @Volatile private var gatt: BluetoothGatt? = null
    @Volatile private var rx: BluetoothGattCharacteristic? = null
    @Volatile private var closed = false

    fun receiveNextRecording(
        scanTimeoutMs: Long,
        waitTimeoutMs: Long,
        commandTimeoutMs: Long,
    ): Map<String, Any> {
        connect(scanTimeoutMs)

        val beforeCount = runCatching { getAudioFileCount(commandTimeoutMs) }.getOrNull()
        val received = try {
            receiveAutoAudio(waitTimeoutMs)
        } catch (timeout: TimeoutException) {
            if (beforeCount == null) throw timeout
            val afterCount = getAudioFileCount(commandTimeoutMs)
            if (afterCount <= beforeCount) {
                throw TimeoutException("No ring recording finished before timeout.")
            }
            downloadAudioFile(afterCount - 1, commandTimeoutMs)
        }

        val files = saveRecording(received.fileIndex, received.data)
        return mapOf(
            "fileIndex" to received.fileIndex,
            "rawPath" to files.raw.absolutePath,
            "uploadPath" to files.ogg.absolutePath,
            "durationSec" to files.durationSec,
            "byteLength" to received.data.size,
            "packetCount" to files.packetCount,
        )
    }

    fun connectAndReadInfo(
        scanTimeoutMs: Long,
        commandTimeoutMs: Long,
    ): Map<String, Any> {
        connect(scanTimeoutMs)
        val info = getSystemInfo(commandTimeoutMs)
        val audioCount = runCatching { getAudioFileCount(commandTimeoutMs) }.getOrNull()
        val values = mutableMapOf<String, Any>(
            "address" to address,
            "firmwareVersion" to info.firmwareVersion,
            "systemTime" to info.systemTime,
            "audioStorageTotal" to info.audioStorageTotal,
            "audioStorageAvailable" to info.audioStorageAvailable,
            "batteryPercent" to info.batteryPercent,
            "batteryCharging" to info.batteryCharging,
            "serialNumber" to info.serialNumber,
            "cpuid" to info.cpuid,
            "model" to info.model,
        )
        if (audioCount != null) values["audioCount"] = audioCount
        return values
    }

    private fun connect(scanTimeoutMs: Long) {
        ensureBluetoothPermission()
        val adapter = BluetoothAdapter.getDefaultAdapter()
            ?: throw IllegalStateException("Bluetooth adapter is unavailable.")
        val scanner = adapter.bluetoothLeScanner
            ?: throw IllegalStateException("Bluetooth LE scanner is unavailable.")

        val foundLatch = CountDownLatch(1)
        var foundDevice: BluetoothDevice? = null
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val device = result.device ?: return
                if (device.address.equals(address, ignoreCase = true)) {
                    foundDevice = device
                    foundLatch.countDown()
                }
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach { onScanResult(0, it) }
            }

            override fun onScanFailed(errorCode: Int) {
                foundLatch.countDown()
            }
        }

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        scanner.startScan(null, settings, callback)
        try {
            if (!foundLatch.await(scanTimeoutMs, TimeUnit.MILLISECONDS)) {
                throw TimeoutException("Timed out scanning for ring $address.")
            }
        } finally {
            runCatching { scanner.stopScan(callback) }
        }

        val device = foundDevice
            ?: throw IllegalStateException("Ring $address was not discovered.")
        val readyLatch = CountDownLatch(1)
        var connectError: String? = null
        val callbackGatt = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    gatt.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    if (!closed) connectError = "Disconnected while connecting, status=$status."
                    readyLatch.countDown()
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    connectError = "Service discovery failed, status=$status."
                    readyLatch.countDown()
                    return
                }
                val service = gatt.getService(serviceUuid)
                val tx = service?.getCharacteristic(txUuid)
                val rxChar = service?.getCharacteristic(rxUuid)
                if (service == null || tx == null || rxChar == null) {
                    connectError = "Ring NUS service or characteristics are missing."
                    readyLatch.countDown()
                    return
                }
                rx = rxChar
                gatt.setCharacteristicNotification(tx, true)
                val descriptor = tx.getDescriptor(cccUuid)
                if (descriptor == null) {
                    readyLatch.countDown()
                    return
                }
                val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    gatt.writeDescriptor(
                        descriptor,
                        BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE,
                    ) == BluetoothGatt.GATT_SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    @Suppress("DEPRECATION")
                    gatt.writeDescriptor(descriptor)
                }
                if (!ok) {
                    connectError = "Failed to enable ring notifications."
                    readyLatch.countDown()
                }
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) {
                if (descriptor.uuid == cccUuid) {
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        connectError = "Notification descriptor write failed, status=$status."
                    }
                    readyLatch.countDown()
                }
            }

            @Deprecated("Deprecated by Android; kept for older devices.")
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
            ) {
                if (characteristic.uuid == txUuid) {
                    @Suppress("DEPRECATION")
                    onNotify(characteristic.value ?: ByteArray(0))
                }
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
            ) {
                if (characteristic.uuid == txUuid) onNotify(value)
            }
        }

        gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            device.connectGatt(context, false, callbackGatt, BluetoothDevice.TRANSPORT_LE)
        } else {
            @Suppress("DEPRECATION")
            device.connectGatt(context, false, callbackGatt)
        }
        if (!readyLatch.await(45_000, TimeUnit.MILLISECONDS)) {
            throw TimeoutException("Timed out connecting to ring GATT.")
        }
        connectError?.let { throw IllegalStateException(it) }
        if (gatt == null || rx == null) {
            throw IllegalStateException("Ring GATT connection was not established.")
        }
    }

    private fun onNotify(value: ByteArray) {
        try {
            PacketStream.feed(value).forEach(dispatcher::push)
        } catch (error: Throwable) {
            dispatcher.fail(error)
        }
    }

    private fun getAudioFileCount(timeoutMs: Long): Int {
        val packet = request(
            command = COMMAND_AUDIO_COUNT_REQ,
            responseCommand = COMMAND_AUDIO_COUNT_RESP,
            body = ByteArray(0),
            timeoutMs = timeoutMs,
        )
        val reader = BodyReader(packet.body)
        reader.ensureSuccess()
        return reader.u32()
    }

    private fun getSystemInfo(timeoutMs: Long): RingSystemInfo {
        val packet = request(
            command = COMMAND_SYSTEM_INFO_REQ,
            responseCommand = COMMAND_SYSTEM_INFO_RESP,
            body = ByteArray(0),
            timeoutMs = timeoutMs,
        )
        val reader = BodyReader(packet.body)
        reader.ensureSuccess()
        return RingSystemInfo(
            firmwareVersion = reader.stringU16(),
            systemTime = reader.u32(),
            audioStorageTotal = reader.u32(),
            audioStorageAvailable = reader.u32(),
            batteryPercent = reader.u16(),
            batteryCharging = reader.u8() != 0,
            serialNumber = reader.stringU16(),
            cpuid = reader.stringU16(),
            model = reader.stringU16(),
        )
    }

    private fun receiveAutoAudio(timeoutMs: Long): ReceivedAudio {
        val first = dispatcher.waitFor(COMMAND_AUDIO_DATA_FRAME, timeoutMs)
        var frame = parseAudioFrame(first.body)
        val fileIndex = frame.fileIndex
        val received = ByteArrayOutputStream()
        while (true) {
            appendFrame(received, frame, fileIndex)
            if (frame.isEnd) {
                return ReceivedAudio(fileIndex, received.toByteArray())
            }
            frame = waitAudioFrame(fileIndex, timeoutMs)
        }
    }

    private fun downloadAudioFile(fileIndex: Int, timeoutMs: Long): ReceivedAudio {
        dispatcher.drain(COMMAND_AUDIO_FILE_INFO_RESP)
        dispatcher.drain(COMMAND_AUDIO_DATA_FRAME)
        writePacket(
            COMMAND_AUDIO_START_EXTRACT_QUICK,
            bodyOf { u16(0); u32(fileIndex) },
        )
        val info = parseAudioInfo(
            dispatcher.waitFor(COMMAND_AUDIO_FILE_INFO_RESP, timeoutMs).body,
        )
        if (info.fileIndex != fileIndex) {
            throw IllegalStateException(
                "Audio metadata index mismatch: expected $fileIndex, got ${info.fileIndex}.",
            )
        }
        val received = ByteArrayOutputStream()
        var retries = 0
        while (received.size() < info.dataSize) {
            val frame = try {
                waitAudioFrame(fileIndex, timeoutMs)
            } catch (timeout: TimeoutException) {
                retries += 1
                if (retries > 3) throw timeout
                requestAudioOffset(fileIndex, received.size())
                continue
            }
            if (frame.frameOffset > received.size()) {
                retries += 1
                if (retries > 3) {
                    throw IllegalStateException(
                        "Audio frame gap at ${received.size()}, got ${frame.frameOffset}.",
                    )
                }
                requestAudioOffset(fileIndex, received.size())
                continue
            }
            appendFrame(received, frame, fileIndex, info.dataSize)
            retries = 0
            if (frame.isEnd && received.size() < info.dataSize) {
                requestAudioOffset(fileIndex, received.size())
            }
        }
        return ReceivedAudio(fileIndex, received.toByteArray().copyOf(info.dataSize))
    }

    private fun waitAudioFrame(fileIndex: Int, timeoutMs: Long): AudioFrame {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (true) {
            val remaining = deadline - System.currentTimeMillis()
            if (remaining <= 0) {
                throw TimeoutException("Timed out waiting for audio frame.")
            }
            val frame = parseAudioFrame(
                dispatcher.waitFor(COMMAND_AUDIO_DATA_FRAME, remaining).body,
            )
            if (frame.fileIndex == fileIndex) return frame
        }
    }

    private fun requestAudioOffset(fileIndex: Int, offset: Int) {
        writePacket(
            COMMAND_AUDIO_NEXT_FRAME,
            bodyOf {
                u16(0)
                u32(fileIndex)
                u32(offset)
                u16(0)
            },
        )
    }

    private fun appendFrame(
        out: ByteArrayOutputStream,
        frame: AudioFrame,
        fileIndex: Int,
        maxSize: Int? = null,
    ) {
        if (frame.fileIndex != fileIndex) {
            throw IllegalStateException("Audio file index mismatch.")
        }
        if (frame.frameOffset > out.size()) {
            throw IllegalStateException(
                "Audio frame gap at ${out.size()}, got ${frame.frameOffset}.",
            )
        }
        val overlap = out.size() - frame.frameOffset
        if (overlap < frame.data.size) {
            val start = max(0, overlap)
            val remaining = maxSize?.let { max(0, it - out.size()) }
                ?: (frame.data.size - start)
            val count = min(frame.data.size - start, remaining)
            if (count > 0) out.write(frame.data, start, count)
        }
    }

    private fun parseAudioInfo(body: ByteArray): AudioInfo {
        val reader = BodyReader(body)
        reader.ensureSuccess()
        return AudioInfo(
            fileIndex = reader.u32(),
            recordTime = reader.u32(),
            dataSize = reader.u32(),
        )
    }

    private fun parseAudioFrame(body: ByteArray): AudioFrame {
        val reader = BodyReader(body)
        reader.ensureSuccess()
        val fileIndex = reader.u32()
        val offset = reader.u32()
        val size = reader.u32()
        val isEnd = reader.u8() != 0
        val data = reader.bytes(size)
        return AudioFrame(fileIndex, offset, isEnd, data)
    }

    private fun request(
        command: Int,
        responseCommand: Int,
        body: ByteArray,
        timeoutMs: Long,
    ): Packet {
        dispatcher.drain(responseCommand)
        writePacket(command, body)
        return dispatcher.waitFor(responseCommand, timeoutMs)
    }

    private fun writePacket(command: Int, body: ByteArray) {
        write(encodePacket(command, body))
    }

    private fun write(payload: ByteArray) {
        val currentGatt = gatt ?: throw IllegalStateException("Ring is not connected.")
        val currentRx = rx ?: throw IllegalStateException("Ring RX characteristic is missing.")
        currentRx.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        var offset = 0
        while (offset < payload.size) {
            val end = min(payload.size, offset + 20)
            val chunk = payload.copyOfRange(offset, end)
            val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                currentGatt.writeCharacteristic(
                    currentRx,
                    chunk,
                    BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE,
                ) == BluetoothGatt.GATT_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                currentRx.value = chunk
                @Suppress("DEPRECATION")
                currentGatt.writeCharacteristic(currentRx)
            }
            if (!ok) throw IllegalStateException("BLE write failed.")
            Thread.sleep(6)
            offset = end
        }
    }

    private fun saveRecording(fileIndex: Int, raw: ByteArray): SavedRingFiles {
        val packets = parsePacketizedSpeex(raw)
        val ogg = buildOggSpeex(packets)
        val dir = File(context.filesDir, "ring_recordings")
        if (!dir.exists()) dir.mkdirs()
        val stamp = System.currentTimeMillis()
        val rawFile = File(dir, "ring_${fileIndex}_$stamp.bin")
        val oggFile = File(dir, "ring_${fileIndex}_$stamp.ogg")
        rawFile.writeBytes(raw)
        oggFile.writeBytes(ogg)
        val durationSec = max(1, ceil(packets.size * 20.0 / 1000.0).toInt())
        return SavedRingFiles(rawFile, oggFile, durationSec, packets.size)
    }

    private fun ensureBluetoothPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val scan = context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)
            val connect = context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
            if (scan != PackageManager.PERMISSION_GRANTED ||
                connect != PackageManager.PERMISSION_GRANTED
            ) {
                throw SecurityException("Bluetooth scan/connect permission is missing.")
            }
        }
    }

    fun close() {
        closed = true
        runCatching { gatt?.disconnect() }
        runCatching { gatt?.close() }
        gatt = null
        rx = null
        dispatcher.close()
    }
}

private object PacketStream {
    private val buffer = ArrayList<Byte>()

    @Synchronized
    fun feed(chunk: ByteArray): List<Packet> {
        chunk.forEach { buffer.add(it) }
        val packets = mutableListOf<Packet>()
        while (true) {
            while (buffer.isNotEmpty() && u8(buffer[0]) != HEADER_MAGIC) {
                buffer.removeAt(0)
            }
            if (buffer.size < 11) break
            val bodyLength = u32(buffer, 5)
            if (bodyLength < 0 || bodyLength > 5120) {
                buffer.removeAt(0)
                continue
            }
            val packetLength = 11 + bodyLength
            if (buffer.size < packetLength) break
            val version = u16(buffer, 1)
            val command = u16(buffer, 3)
            val bodyCrc = u16(buffer, 9)
            val body = ByteArray(bodyLength)
            for (i in 0 until bodyLength) body[i] = buffer[11 + i]
            repeat(packetLength) { buffer.removeAt(0) }
            if (version > PROTOCOL_VERSION) {
                throw IllegalStateException("Unsupported ring protocol version $version.")
            }
            if (body.isNotEmpty() && crc16(body) != bodyCrc) {
                throw IllegalStateException("Ring packet CRC mismatch.")
            }
            packets.add(Packet(command, body))
        }
        return packets
    }
}

private class PacketDispatcher {
    private val lock = Object()
    private val queues = mutableMapOf<Int, ArrayDeque<Packet>>()
    private var error: Throwable? = null
    private var closed = false

    fun push(packet: Packet) {
        synchronized(lock) {
            queues.getOrPut(packet.command) { ArrayDeque() }.add(packet)
            lock.notifyAll()
        }
    }

    fun fail(cause: Throwable) {
        synchronized(lock) {
            error = cause
            lock.notifyAll()
        }
    }

    fun drain(command: Int) {
        synchronized(lock) {
            queues[command]?.clear()
        }
    }

    fun waitFor(command: Int, timeoutMs: Long): Packet {
        val deadline = System.currentTimeMillis() + timeoutMs
        synchronized(lock) {
            while (true) {
                error?.let { throw it }
                if (closed) throw IllegalStateException("Ring connection closed.")
                val queue = queues[command]
                if (queue != null && queue.isNotEmpty()) {
                    return queue.removeFirst()
                }
                val remaining = deadline - System.currentTimeMillis()
                if (remaining <= 0) {
                    throw TimeoutException("Timed out waiting for command 0x${command.toString(16)}.")
                }
                lock.wait(min(remaining, 1000))
            }
        }
    }

    fun close() {
        synchronized(lock) {
            closed = true
            lock.notifyAll()
        }
    }
}

private class BodyReader(private val data: ByteArray) {
    private var offset = 0

    fun ensureSuccess() {
        val code = u16()
        if (code != 0) throw IllegalStateException("Ring returned error code $code.")
    }

    fun u8(): Int {
        if (offset >= data.size) throw IllegalStateException("Unexpected end of ring packet.")
        return data[offset++].toInt() and 0xFF
    }

    fun u16(): Int {
        if (offset + 2 > data.size) throw IllegalStateException("Unexpected end of ring packet.")
        val value = ((data[offset].toInt() and 0xFF) shl 8) or
            (data[offset + 1].toInt() and 0xFF)
        offset += 2
        return value
    }

    fun u32(): Int {
        if (offset + 4 > data.size) throw IllegalStateException("Unexpected end of ring packet.")
        val value = ((data[offset].toInt() and 0xFF) shl 24) or
            ((data[offset + 1].toInt() and 0xFF) shl 16) or
            ((data[offset + 2].toInt() and 0xFF) shl 8) or
            (data[offset + 3].toInt() and 0xFF)
        offset += 4
        return value
    }

    fun bytes(length: Int): ByteArray {
        if (length < 0 || offset + length > data.size) {
            throw IllegalStateException("Invalid ring packet length.")
        }
        val out = data.copyOfRange(offset, offset + length)
        offset += length
        return out
    }

    fun stringU16(): String {
        val length = u16()
        return bytes(length).toString(Charsets.UTF_8)
    }
}

private class BodyWriter {
    private val out = ByteArrayOutputStream()

    fun u16(value: Int) {
        out.write((value shr 8) and 0xFF)
        out.write(value and 0xFF)
    }

    fun u32(value: Int) {
        out.write((value shr 24) and 0xFF)
        out.write((value shr 16) and 0xFF)
        out.write((value shr 8) and 0xFF)
        out.write(value and 0xFF)
    }

    fun build(): ByteArray = out.toByteArray()
}

private fun bodyOf(block: BodyWriter.() -> Unit): ByteArray {
    val writer = BodyWriter()
    writer.block()
    return writer.build()
}

private fun encodePacket(command: Int, body: ByteArray): ByteArray {
    val out = ByteArrayOutputStream()
    out.write(HEADER_MAGIC)
    out.write((PROTOCOL_VERSION shr 8) and 0xFF)
    out.write(PROTOCOL_VERSION and 0xFF)
    out.write((command shr 8) and 0xFF)
    out.write(command and 0xFF)
    out.write((body.size shr 24) and 0xFF)
    out.write((body.size shr 16) and 0xFF)
    out.write((body.size shr 8) and 0xFF)
    out.write(body.size and 0xFF)
    val crc = if (body.isEmpty()) 0 else crc16(body)
    out.write((crc shr 8) and 0xFF)
    out.write(crc and 0xFF)
    out.write(body)
    return out.toByteArray()
}

private fun parsePacketizedSpeex(raw: ByteArray): List<ByteArray> {
    val packets = mutableListOf<ByteArray>()
    var offset = 0
    while (offset + 2 <= raw.size) {
        val length = (raw[offset].toInt() and 0xFF) or
            ((raw[offset + 1].toInt() and 0xFF) shl 8)
        if (length == 0) break
        if (length > 540 || offset + 2 + length > raw.size) {
            throw IllegalStateException("Invalid ring Speex packet length $length.")
        }
        packets.add(raw.copyOfRange(offset + 2, offset + 2 + length))
        offset += 2 + length
    }
    if (packets.isEmpty()) {
        throw IllegalStateException("Ring recording did not contain Speex packets.")
    }
    return packets
}

private fun buildOggSpeex(packets: List<ByteArray>): ByteArray {
    val serial = 0x564F5247
    val frameSize = 320
    val pages = ByteArrayOutputStream()
    pages.write(
        buildOggPage(
            packet = speexHeader(),
            headerType = 2,
            granule = 0,
            serial = serial,
            sequence = 0,
        ),
    )
    val vendor = "ring-sound-android".toByteArray(Charsets.UTF_8)
    val comments = ByteBuffer.allocate(4 + vendor.size + 4)
        .order(ByteOrder.LITTLE_ENDIAN)
        .putInt(vendor.size)
        .put(vendor)
        .putInt(0)
        .array()
    pages.write(
        buildOggPage(
            packet = comments,
            headerType = 0,
            granule = 0,
            serial = serial,
            sequence = 1,
        ),
    )
    var granule = 0L
    packets.forEachIndexed { index, packet ->
        granule += frameSize
        pages.write(
            buildOggPage(
                packet = packet,
                headerType = if (index == packets.lastIndex) 4 else 0,
                granule = granule,
                serial = serial,
                sequence = index + 2,
            ),
        )
    }
    return pages.toByteArray()
}

private fun speexHeader(): ByteArray {
    val version = ByteArray(20)
    "speex-1.2.1".toByteArray(Charsets.US_ASCII).copyInto(version)
    val out = ByteArrayOutputStream()
    val label = ByteArray(8)
    "Speex   ".toByteArray(Charsets.US_ASCII).copyInto(label)
    out.write(label)
    out.write(version)
    val ints = intArrayOf(
        1,
        80,
        16_000,
        1,
        4,
        1,
        -1,
        320,
        0,
        1,
        0,
        0,
        0,
    )
    ints.forEach { out.writeIntLE(it) }
    return out.toByteArray()
}

private fun buildOggPage(
    packet: ByteArray,
    headerType: Int,
    granule: Long,
    serial: Int,
    sequence: Int,
): ByteArray {
    val lacing = mutableListOf<Int>()
    var remaining = packet.size
    while (remaining >= 255) {
        lacing.add(255)
        remaining -= 255
    }
    lacing.add(remaining)
    if (lacing.size > 255) throw IllegalStateException("Ogg packet too large.")

    val out = ByteArrayOutputStream()
    out.write("OggS".toByteArray(Charsets.US_ASCII))
    out.write(0)
    out.write(headerType and 0xFF)
    out.writeLongLE(granule)
    out.writeIntLE(serial)
    out.writeIntLE(sequence)
    out.writeIntLE(0)
    out.write(lacing.size)
    lacing.forEach { out.write(it) }
    out.write(packet)
    val page = out.toByteArray()
    val crc = oggCrc(page)
    page[22] = (crc and 0xFF).toByte()
    page[23] = ((crc ushr 8) and 0xFF).toByte()
    page[24] = ((crc ushr 16) and 0xFF).toByte()
    page[25] = ((crc ushr 24) and 0xFF).toByte()
    return page
}

private fun crc16(data: ByteArray): Int {
    var crc = 0xFFFF
    for (byte in data) {
        crc = ((crc ushr 8) or ((crc shl 8) and 0xFFFF)) and 0xFFFF
        crc = crc xor (byte.toInt() and 0xFF)
        crc = crc xor ((crc and 0xFF) ushr 4)
        crc = crc xor ((crc shl 8) shl 4)
        crc = crc xor (((crc and 0xFF) shl 4) shl 1)
        crc = crc and 0xFFFF
    }
    return crc
}

private fun oggCrc(data: ByteArray): Int {
    var crc = 0
    for (byte in data) {
        crc = crc xor ((byte.toInt() and 0xFF) shl 24)
        repeat(8) {
            crc = if ((crc and 0x80000000.toInt()) != 0) {
                (crc shl 1) xor 0x04C11DB7
            } else {
                crc shl 1
            }
        }
    }
    return crc
}

private fun ByteArrayOutputStream.writeIntLE(value: Int) {
    write(value and 0xFF)
    write((value ushr 8) and 0xFF)
    write((value ushr 16) and 0xFF)
    write((value ushr 24) and 0xFF)
}

private fun ByteArrayOutputStream.writeLongLE(value: Long) {
    write((value and 0xFF).toInt())
    write(((value ushr 8) and 0xFF).toInt())
    write(((value ushr 16) and 0xFF).toInt())
    write(((value ushr 24) and 0xFF).toInt())
    write(((value ushr 32) and 0xFF).toInt())
    write(((value ushr 40) and 0xFF).toInt())
    write(((value ushr 48) and 0xFF).toInt())
    write(((value ushr 56) and 0xFF).toInt())
}

private fun u8(byte: Byte): Int = byte.toInt() and 0xFF
private fun u16(bytes: List<Byte>, offset: Int): Int =
    ((bytes[offset].toInt() and 0xFF) shl 8) or
        (bytes[offset + 1].toInt() and 0xFF)

private fun u32(bytes: List<Byte>, offset: Int): Int =
    ((bytes[offset].toInt() and 0xFF) shl 24) or
        ((bytes[offset + 1].toInt() and 0xFF) shl 16) or
        ((bytes[offset + 2].toInt() and 0xFF) shl 8) or
        (bytes[offset + 3].toInt() and 0xFF)

private data class Packet(val command: Int, val body: ByteArray)
private data class AudioInfo(val fileIndex: Int, val recordTime: Int, val dataSize: Int)
private data class AudioFrame(
    val fileIndex: Int,
    val frameOffset: Int,
    val isEnd: Boolean,
    val data: ByteArray,
)
private data class ReceivedAudio(val fileIndex: Int, val data: ByteArray)
private data class RingSystemInfo(
    val firmwareVersion: String,
    val systemTime: Int,
    val audioStorageTotal: Int,
    val audioStorageAvailable: Int,
    val batteryPercent: Int,
    val batteryCharging: Boolean,
    val serialNumber: String,
    val cpuid: String,
    val model: String,
)
private data class SavedRingFiles(
    val raw: File,
    val ogg: File,
    val durationSec: Int,
    val packetCount: Int,
)
