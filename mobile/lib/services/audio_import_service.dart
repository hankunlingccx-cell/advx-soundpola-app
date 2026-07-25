import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../audio/audio_features.dart';
import '../visual/audio_feature_timeline.dart';

class AudioImportResult {
  const AudioImportResult({
    required this.path,
    required this.durationSec,
    required this.visualSeed,
    required this.timeline,
    this.suggestedTitle,
  });

  final String path;
  final int durationSec;
  final int visualSeed;
  final AudioFeatureTimeline timeline;
  final String? suggestedTitle;
}

/// Picks a local audio file, copies into app `recordings/`, probes duration.
class AudioImportService {
  AudioImportService._();
  static final AudioImportService instance = AudioImportService._();

  static const _minDurationSec = 3;
  static const _allowedExt = {
    'm4a',
    'mp3',
    'wav',
    'aac',
    'ogg',
    'flac',
    'caf',
  };

  /// Returns null if user cancels. Throws [StateError] on invalid file.
  Future<AudioImportResult?> pickAndImport() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExt.toList(),
      allowMultiple: false,
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return null;

    final file = picked.files.single;
    final sourcePath = file.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      throw StateError('无法读取所选文件路径');
    }

    final ext = (file.extension ?? _extOf(sourcePath)).toLowerCase();
    if (!_allowedExt.contains(ext)) {
      throw StateError('不支持的音频格式（.$ext）');
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('所选文件不存在');
    }

    final destPath = await _copyToRecordings(source, ext);
    final duration = await _probeDuration(destPath);
    final durationSec = duration.inMilliseconds > 0
        ? (duration.inMilliseconds / 1000).ceil().clamp(1, kMaxRecordingDurationSec)
        : 0;

    if (durationSec < _minDurationSec) {
      try {
        await File(destPath).delete();
      } catch (_) {}
      throw StateError('音频过短（至少 $_minDurationSec 秒）');
    }
    if (duration.inSeconds > kMaxRecordingDurationSec) {
      // Soft trim note: we keep the file but cap session duration for bake budget.
      debugPrint(
        'AudioImport: duration ${duration.inSeconds}s exceeds cap; '
        'session capped to ${kMaxRecordingDurationSec}s',
      );
    }

    final seed = DateTime.now().millisecondsSinceEpoch % 900000 + 1000;
    final timeline = synthesizeDriveTimeline(
      durationMs: durationSec * 1000,
      seed: seed,
    );

    final title = _titleFromName(file.name);
    return AudioImportResult(
      path: destPath,
      durationSec: durationSec,
      visualSeed: seed,
      timeline: timeline,
      suggestedTitle: title,
    );
  }

  Future<String> _copyToRecordings(File source, String ext) async {
    final dir = await getApplicationDocumentsDirectory();
    final recordings = Directory('${dir.path}/recordings');
    if (!await recordings.exists()) {
      await recordings.create(recursive: true);
    }
    final name = 'imp_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final dest = '${recordings.path}${Platform.pathSeparator}$name';
    await source.copy(dest);
    return dest;
  }

  Future<Duration> _probeDuration(String path) async {
    final player = AudioPlayer();
    try {
      await player.setSource(DeviceFileSource(path));
      // Some platforms need a short wait before duration is known.
      for (var i = 0; i < 20; i++) {
        final d = player.source == null
            ? Duration.zero
            : await player.getDuration() ?? Duration.zero;
        if (d > Duration.zero) return d;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return await player.getDuration() ?? Duration.zero;
    } finally {
      await player.dispose();
    }
  }

  static String _extOf(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0 || i == path.length - 1) return '';
    return path.substring(i + 1);
  }

  static String? _titleFromName(String name) {
    var base = name;
    final i = base.lastIndexOf('.');
    if (i > 0) base = base.substring(0, i);
    base = base.trim();
    if (base.isEmpty) return null;
    if (base.length > 40) base = base.substring(0, 40);
    return base;
  }

  /// Soft deterministic drive for imported audio (no live mic analysis).
  static AudioFeatureTimeline synthesizeDriveTimeline({
    required int durationMs,
    required int seed,
  }) {
    final out = AudioFeatureTimeline();
    final rng = math.Random(seed);
    final phaseA = rng.nextDouble() * math.pi * 2;
    final phaseB = rng.nextDouble() * math.pi * 2;
    final step = 40;
    for (var t = 0; t <= durationMs; t += step) {
      final u = durationMs <= 0 ? 0.0 : t / durationMs;
      final pulse = 0.5 +
          0.5 *
              math.sin(u * math.pi * 4 + phaseA) *
              math.sin(u * math.pi * 1.7 + phaseB);
      final energy = (0.12 + pulse * 0.35 + rng.nextDouble() * 0.04)
          .clamp(0.05, 0.85);
      final bass = (0.15 + energy * 0.45 + math.sin(u * 6 + phaseA) * 0.08)
          .clamp(0.05, 1.0);
      final mid = (0.18 + energy * 0.4 + math.sin(u * 9 + phaseB) * 0.1)
          .clamp(0.05, 1.0);
      final treble =
          (0.1 + energy * 0.35 + math.sin(u * 14 + phaseA * 0.5) * 0.12)
              .clamp(0.05, 1.0);
      final flux = (energy * 0.25 + rng.nextDouble() * 0.08).clamp(0.0, 1.0);
      final onset = (pulse > 0.92 && rng.nextDouble() > 0.7)
          ? (0.4 + rng.nextDouble() * 0.4)
          : 0.0;
      final centroid = (0.25 + mid * 0.35 + treble * 0.25).clamp(0.0, 1.0);
      final spectrum = List<double>.generate(AudioFeatures.spectrumBinCount, (i) {
        final x = i / (AudioFeatures.spectrumBinCount - 1);
        return (bass * (1 - x) * 0.7 +
                mid * math.exp(-math.pow(x - 0.45, 2) * 8) +
                treble * x * 0.8 +
                energy * 0.15)
            .clamp(0.0, 1.0);
      });
      out.samples.add(
        AudioFeatureSample(
          timeMs: t,
          features: AudioFeatures(
            rms: energy,
            gatedRms: energy,
            fastEnvelope: energy,
            slowEnvelope: energy * 0.85,
            bass: bass,
            lowMid: (bass + mid) * 0.5,
            mid: mid,
            highMid: (mid + treble) * 0.5,
            treble: treble,
            spectralCentroid: centroid,
            spectralFlux: flux,
            onset: onset,
            zeroCrossingRate: 0.15 + treble * 0.25,
            spectrum: spectrum,
          ),
        ),
      );
    }
    return out;
  }
}
