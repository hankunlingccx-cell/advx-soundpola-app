import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../audio/audio_features.dart';
import '../cloud/cloud_prefetch.dart';
import '../data/session.dart';
import '../data/sound_repository.dart';
import '../widgets/sound_visual.dart';
import 'audio_feature_timeline.dart';
import 'sound_package_store.dart';
import 'visual_manifest.dart';
import 'visual_mp4_encoder.dart';

/// Encodes RGBA → JPEG off the UI thread.
Uint8List _encodeJpegIsolate(Map<String, dynamic> args) {
  final w = args['w'] as int;
  final h = args['h'] as int;
  final quality = args['q'] as int;
  final rgba = args['rgba'] as Uint8List;
  final image = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    rowStride: w * 4,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

/// Offline: timeline + seed → indexed MJPEG + cover + manifest.
class VisualBakeService {
  VisualBakeService._();
  static final VisualBakeService instance = VisualBakeService._();

  bool _busy = false;
  bool get isBusy => _busy;

  Future<void> bakeSound(
    String soundId, {
    int? visualSeed,
    int? durationSec,
    int fps = kVisualBakeFps,
    int size = kVisualBakeSize,
    int jpegQuality = kVisualBakeJpegQuality,
  }) async {
    if (_busy) return;
    _busy = true;
    final repo = SoundRepository.instance;
    final item = repo.get(soundId);
    final seed = visualSeed ?? item?.visualSeed;
    final durSec = durationSec ?? item?.durationSec;
    if (seed == null || durSec == null) {
      _busy = false;
      return;
    }

    void patchStatus(
      VisualBakeStatus status, {
      String? error,
      SoundPackagePaths? paths,
      bool clearError = false,
    }) {
      if (repo.get(soundId) == null) {
        if (status == VisualBakeStatus.failed) {
          if (RecordingSession.pendingSoundId == soundId) {
            RecordingSession.pendingBakeError = error;
          }
        } else if (status == VisualBakeStatus.ready &&
            RecordingSession.pendingSoundId == soundId) {
          RecordingSession.pendingBakeError = null;
        }
        return;
      }
      repo.update(
        soundId,
        (s) => s.copyWith(
          visualBakeStatus: status,
          visualBakeError: error,
          clearVisualBakeError: clearError,
          packageDir: paths?.dirPath,
          coverPath: paths?.coverPath,
          visualMjpgPath: paths?.mjpgPath,
          visualIdxPath: paths?.idxPath,
          visualManifestPath: paths?.manifestPath,
          visualMp4Path: paths?.mp4Path,
          audioFeaturesPath: paths?.featuresPath,
          audioPath: paths?.audioPath,
        ),
      );
    }

    patchStatus(VisualBakeStatus.processingVisual, clearError: true);

    try {
      final store = SoundPackageStore.instance;
      final featuresFile = await store.featuresFile(soundId);
      if (!await featuresFile.exists()) {
        throw StateError('缺少 audio_features.bin，无法生成可视化帧');
      }
      final timeline =
          AudioFeatureTimeline.decode(await featuresFile.readAsBytes());
      final durationMs = _maxInt(
        durSec * 1000,
        timeline.durationMs,
      );
      if (durationMs <= 0) {
        throw StateError('时长无效');
      }

      final frameIntervalMs = (1000 / fps).round().clamp(40, 120);
      final frameCount = _maxInt(1, (durationMs / frameIntervalMs).ceil());

      final engine = SoundVisualOffscreen(
        seed: seed,
        quality: VisualQuality.low,
      );

      final mjpgPath = (await store.mjpgFile(soundId)).path;
      final mjpgFile = File(mjpgPath);
      if (await mjpgFile.exists()) await mjpgFile.delete();
      final sink = mjpgFile.openWrite();

      final entries = <VisualFrameIndexEntry>[];
      var offset = 0;
      var bestScore = -1.0;
      var bestFrame = 0;
      Uint8List? bestJpeg;

      patchStatus(VisualBakeStatus.indexing);

      for (var i = 0; i < frameCount; i++) {
        final timeMs = i * frameIntervalMs;
        if (timeMs > durationMs) break;
        final dt = frameIntervalMs / 1000.0;
        engine.seek(timeline, timeMs, dt: dt);

        final image = await engine.renderImage(size, size);
        final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        if (bd == null) continue;
        final rgba = bd.buffer.asUint8List(
          bd.offsetInBytes,
          bd.lengthInBytes,
        );
        final jpeg = await compute(_encodeJpegIsolate, {
          'w': size,
          'h': size,
          'q': jpegQuality,
          // Copy — ByteData view is not reliably transferable across isolates.
          'rgba': Uint8List.fromList(rgba),
        });

        sink.add(jpeg);
        entries.add(
          VisualFrameIndexEntry(
            frame: entries.length,
            timeMs: timeMs,
            offset: offset,
            length: jpeg.length,
            width: size,
            height: size,
          ),
        );
        offset += jpeg.length;

        if (timeMs >= 500) {
          final f = timeline.sampleAt(timeMs);
          final energy = f.gatedRms.clamp(0.0, 1.0);
          final onsetPen = (f.onset - 0.35).abs();
          final overPen = energy > 0.92 ? (energy - 0.92) * 4 : 0.0;
          final score = energy * 1.2 - onsetPen * 0.5 - overPen;
          if (score > bestScore) {
            bestScore = score;
            bestFrame = entries.length - 1;
            bestJpeg = jpeg;
          }
        }

        // Yield every frame so recording / playback UI can keep a frame budget.
        await Future<void>.delayed(Duration.zero);
      }

      await sink.flush();
      await sink.close();

      if (entries.isEmpty) {
        throw StateError('未生成任何可视化帧');
      }

      if (bestJpeg == null) {
        final reader = IndexedMjpegReader(
          mjpgFile: mjpgFile,
          index: VisualFrameIndex(entries),
        );
        await reader.open();
        bestJpeg = await reader.readEntry(entries.first);
        await reader.close();
        bestFrame = 0;
      }

      if (bestJpeg != null) {
        await (await store.coverFile(soundId))
            .writeAsBytes(bestJpeg, flush: true);
      }

      await VisualFrameIndex(entries).save(await store.idxFile(soundId));

      final manifest = VisualManifest(
        width: size,
        height: size,
        fps: fps.toDouble(),
        frameCount: entries.length,
        durationMs: durationMs,
        jpegQuality: jpegQuality,
        audioId: soundId,
        visualSeed: seed,
        rendererVersion: kSoundVisualRendererVersion,
        coverFrame: bestFrame,
      );
      await manifest.save(await store.manifestFile(soundId));

      // Best-effort H.264 for cloud video upload (local play still uses MJPEG).
      String? mp4Path;
      try {
        mp4Path = await VisualMp4Encoder.instance.encodeFromPackage(
          soundId: soundId,
          mjpgPath: mjpgPath,
          idxPath: (await store.idxFile(soundId)).path,
          fps: fps.toDouble(),
          width: size,
          height: size,
        );
      } catch (e) {
        debugPrint('VisualBakeService mp4 encode skipped: $e');
      }
      if (mp4Path != null &&
          RecordingSession.pendingSoundId == soundId) {
        RecordingSession.pendingMp4Path = mp4Path;
      }

      final paths = SoundPackagePaths(
        dirPath: await store.packagePath(soundId),
        audioPath: (await store.audioFile(soundId)).path,
        featuresPath: featuresFile.path,
        mjpgPath: mjpgPath,
        idxPath: (await store.idxFile(soundId)).path,
        manifestPath: (await store.manifestFile(soundId)).path,
        coverPath: (await store.coverFile(soundId)).path,
        mp4Path: mp4Path,
      );

      patchStatus(
        VisualBakeStatus.ready,
        paths: paths,
        clearError: true,
      );
      // Draft 已入库时后台预上传，缩短后续 NFC 写入等待。
      if (repo.get(soundId) != null) {
        CloudPrefetchService.instance.schedule(soundId);
      }
    } catch (e, st) {
      debugPrint('VisualBakeService failed: $e\n$st');
      patchStatus(
        VisualBakeStatus.failed,
        error: e.toString(),
      );
      // bake 失败仍尽力仅传音频，Press 时少等一轮。
      if (repo.get(soundId) != null) {
        CloudPrefetchService.instance.schedule(soundId);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> retry(String soundId) => bakeSound(soundId);

  /// Wait until Indexed-MJPEG bake is [VisualBakeStatus.ready] (or give up).
  ///
  /// Used by Press / cloud upload so MP4 (when available) can be uploaded after
  /// audio. Returns the latest [SoundMemory] (may still be non-ready on timeout/fail).
  Future<SoundMemory?> ensureReady(
    String soundId, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final repo = SoundRepository.instance;
    var item = repo.get(soundId);
    if (item == null) return null;
    if (item.hasIndexedVisual) return item;

    final needsKick = item.visualBakeStatus != VisualBakeStatus.processingVisual &&
        item.visualBakeStatus != VisualBakeStatus.indexing;
    if (needsKick) {
      unawaited(bakeSound(soundId));
    }

    var didRetry = false;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      item = repo.get(soundId);
      if (item == null) return null;
      if (item.hasIndexedVisual) return item;
      if (item.visualBakeStatus == VisualBakeStatus.failed &&
          !_busy &&
          !didRetry) {
        didRetry = true;
        await bakeSound(soundId);
        item = repo.get(soundId);
        if (item != null && item.hasIndexedVisual) return item;
        if (item?.visualBakeStatus == VisualBakeStatus.failed) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return repo.get(soundId);
  }
}

int _maxInt(int a, int b) => a > b ? a : b;
