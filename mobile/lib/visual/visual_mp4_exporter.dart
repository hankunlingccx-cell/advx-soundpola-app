import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'package:image/image.dart' as img;

import '../data/sound_repository.dart';
import 'audio_feature_timeline.dart';
import 'visual_manifest.dart';

/// Decode Indexed-MJPEG → hardware H.264 MP4 for cloud `/video` upload.
class VisualMp4Exporter {
  VisualMp4Exporter._();
  static final VisualMp4Exporter instance = VisualMp4Exporter._();

  /// Returns path to `visual.mp4` next to the package, or null on failure.
  Future<File?> export(SoundMemory item) async {
    if (!item.hasIndexedVisual) return null;
    final mjpgPath = item.visualMjpgPath;
    final idxPath = item.visualIdxPath;
    if (mjpgPath == null || idxPath == null) return null;

    final mjpg = File(mjpgPath);
    final idxFile = File(idxPath);
    if (!await mjpg.exists() || !await idxFile.exists()) return null;

    final index = await VisualFrameIndex.load(idxFile);
    if (index.entries.isEmpty) return null;

    final first = index.entries.first;
    final width = first.width;
    final height = first.height;
    if (width <= 0 || height <= 0 || width.isOdd || height.isOdd) {
      debugPrint(
        '[VisualMp4] unsupported size ${width}x$height (need even dims)',
      );
      return null;
    }

    var fps = kVisualBakeFps;
    final manifestPath = item.visualManifestPath;
    if (manifestPath != null) {
      final manifest = await VisualManifest.load(File(manifestPath));
      if (manifest != null && manifest.fps > 0) {
        fps = manifest.fps.round().clamp(8, 30);
      }
    }

    final outPath = _mp4PathFor(item);
    final out = File(outPath);
    if (await out.exists()) {
      try {
        await out.delete();
      } catch (_) {}
    }

    final reader = IndexedMjpegReader(mjpgFile: mjpg, index: index);
    await reader.open();
    try {
      await FlutterQuickVideoEncoder.setLogLevel(LogLevel.error);
      await FlutterQuickVideoEncoder.setup(
        width: width,
        height: height,
        fps: fps,
        videoBitrate: _bitrateFor(width, height, fps),
        profileLevel: ProfileLevel.baseline31,
        audioChannels: 0,
        audioBitrate: 0,
        sampleRate: 0,
        filepath: outPath,
      );

      final expected = width * height * 4;
      for (final entry in index.entries) {
        final jpeg = await reader.readEntry(entry);
        if (jpeg == null || jpeg.isEmpty) continue;
        final rgba = await compute(_jpegToRgbaIsolate, {
          'jpeg': jpeg,
          'w': width,
          'h': height,
        });
        if (rgba == null || rgba.length != expected) {
          debugPrint(
            '[VisualMp4] skip frame ${entry.frame}: bad rgba '
            '(${rgba?.length} vs $expected)',
          );
          continue;
        }
        await FlutterQuickVideoEncoder.appendVideoFrame(rgba);
      }
      await FlutterQuickVideoEncoder.finish();
    } catch (e, st) {
      debugPrint('[VisualMp4] export failed: $e\n$st');
      try {
        await FlutterQuickVideoEncoder.finish();
      } catch (_) {}
      return null;
    } finally {
      await reader.close();
    }

    if (!await out.exists() || await out.length() <= 0) {
      debugPrint('[VisualMp4] output missing or empty: $outPath');
      return null;
    }
    debugPrint(
      '[VisualMp4] wrote $outPath (${await out.length()} bytes, '
      '${index.entries.length} frames @ ${fps}fps)',
    );
    return out;
  }

  static String _mp4PathFor(SoundMemory item) {
    final dir = item.packageDir;
    if (dir != null && dir.isNotEmpty) {
      return '$dir${Platform.pathSeparator}visual.mp4';
    }
    final mjpg = item.visualMjpgPath!;
    final i = mjpg.lastIndexOf(Platform.pathSeparator);
    final parent = i >= 0 ? mjpg.substring(0, i) : '.';
    return '$parent${Platform.pathSeparator}visual.mp4';
  }

  static int _bitrateFor(int w, int h, int fps) {
    // ~0.12 bpp heuristic for particle art; clamp for cloud preview.
    final raw = (w * h * fps * 0.12).round();
    return raw.clamp(400000, 2500000);
  }
}

/// Isolate: JPEG bytes → tightly sized RGBA (may letterbox/crop to w×h).
Uint8List? _jpegToRgbaIsolate(Map<String, dynamic> args) {
  final jpeg = args['jpeg'] as Uint8List;
  final w = args['w'] as int;
  final h = args['h'] as int;
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) return null;
  final resized = (decoded.width == w && decoded.height == h)
      ? decoded
      : img.copyResize(decoded, width: w, height: h);
  return Uint8List.fromList(
    resized.getBytes(order: img.ChannelOrder.rgba),
  );
}
