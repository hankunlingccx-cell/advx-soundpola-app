import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sound_package_store.dart';
import 'visual_manifest.dart';

/// Encodes Indexed-MJPEG → H.264 MP4 via Android MediaCodec (cloud upload).
class VisualMp4Encoder {
  VisualMp4Encoder._();
  static final VisualMp4Encoder instance = VisualMp4Encoder._();

  static const _channel = MethodChannel('soundpola/visual_mp4');

  /// Returns path to `visual.mp4` on success; null when unsupported / failed.
  Future<String?> encodeFromPackage({
    required String soundId,
    required String mjpgPath,
    required String idxPath,
    required double fps,
    required int width,
    required int height,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      debugPrint('[VisualMp4] skip: only Android encoder is available');
      return null;
    }
    final mjpg = File(mjpgPath);
    final idxFile = File(idxPath);
    if (!await mjpg.exists() || !await idxFile.exists()) return null;

    final store = SoundPackageStore.instance;
    final out = await store.mp4File(soundId);
    Directory? framesDir;
    try {
      final index = await VisualFrameIndex.load(idxFile);
      if (index.entries.isEmpty) return null;

      framesDir = Directory(
        '${(await store.packageDir(soundId)).path}${Platform.pathSeparator}_mp4_frames',
      );
      if (await framesDir.exists()) {
        await framesDir.delete(recursive: true);
      }
      await framesDir.create(recursive: true);

      final raf = await mjpg.open();
      try {
        for (var i = 0; i < index.entries.length; i++) {
          final e = index.entries[i];
          await raf.setPosition(e.offset);
          final bytes = await raf.read(e.length);
          final name = 'frame_${i.toString().padLeft(5, '0')}.jpg';
          await File('${framesDir.path}${Platform.pathSeparator}$name')
              .writeAsBytes(bytes, flush: true);
        }
      } finally {
        await raf.close();
      }

      if (await out.exists()) await out.delete();

      final path = await _channel.invokeMethod<String>('encodeJpegDir', {
        'framesDir': framesDir.path,
        'outputPath': out.path,
        'fps': fps.round().clamp(1, 30),
        'width': width,
        'height': height,
      });
      if (path == null || path.isEmpty || !File(path).existsSync()) {
        return null;
      }
      if (await File(path).length() <= 0) return null;
      debugPrint('[VisualMp4] encoded $path (${await File(path).length()} bytes)');
      return path;
    } on MissingPluginException {
      debugPrint('[VisualMp4] plugin missing');
      return null;
    } on PlatformException catch (e) {
      debugPrint('[VisualMp4] encode failed: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[VisualMp4] encode failed: $e');
      return null;
    } finally {
      if (framesDir != null && await framesDir.exists()) {
        try {
          await framesDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}
