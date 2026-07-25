import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'audio_feature_timeline.dart';

/// On-disk layout for one sound memory package:
/// ```
/// sounds/{id}/
///   audio.wav | audio.m4a | audio.ogg   (new phone recordings are PCM16 WAV)
///   visual.mjpg
///   visual.idx
///   visual_manifest.json
///   audio_features.bin
///   cover.jpg
/// ```
class SoundPackageStore {
  SoundPackageStore._();
  static final SoundPackageStore instance = SoundPackageStore._();

  Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}sounds');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> packageDir(String soundId) async {
    final root = await _root();
    final dir = Directory('${root.path}${Platform.pathSeparator}$soundId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _join(Directory dir, String name) =>
      '${dir.path}${Platform.pathSeparator}$name';

  /// Prefer WAV (PCM analysis pipeline); fall back to other imported formats.
  Future<File> audioFile(String soundId) async {
    final dir = await packageDir(soundId);
    for (final name in _audioPackageNames) {
      final file = File(_join(dir, name));
      if (await file.exists()) return file;
    }
    return File(_join(dir, 'audio.m4a'));
  }

  Future<File> featuresFile(String soundId) async =>
      File(_join(await packageDir(soundId), 'audio_features.bin'));

  Future<File> mjpgFile(String soundId) async =>
      File(_join(await packageDir(soundId), 'visual.mjpg'));

  Future<File> idxFile(String soundId) async =>
      File(_join(await packageDir(soundId), 'visual.idx'));

  Future<File> manifestFile(String soundId) async =>
      File(_join(await packageDir(soundId), 'visual_manifest.json'));

  Future<File> coverFile(String soundId) async =>
      File(_join(await packageDir(soundId), 'cover.jpg'));

  Future<String> packagePath(String soundId) async =>
      (await packageDir(soundId)).path;

  static String _audioPackageName(String sourcePath) {
    final lower = sourcePath.toLowerCase();
    if (lower.endsWith('.wav')) return 'audio.wav';
    if (lower.endsWith('.ogg')) return 'audio.ogg';
    if (lower.endsWith('.mp3')) return 'audio.mp3';
    if (lower.endsWith('.aac')) return 'audio.aac';
    if (lower.endsWith('.flac')) return 'audio.flac';
    if (lower.endsWith('.caf')) return 'audio.caf';
    return 'audio.m4a';
  }

  static const _audioPackageNames = [
    'audio.wav',
    'audio.m4a',
    'audio.ogg',
    'audio.mp3',
    'audio.aac',
    'audio.flac',
    'audio.caf',
  ];

  /// Move/copy [sourceAudio] into package under a canonical audio name.
  Future<SoundPackagePaths> materialize({
    required String soundId,
    required String sourceAudioPath,
    required AudioFeatureTimeline timeline,
  }) async {
    final dir = await packageDir(soundId);
    final audio = File(_join(dir, _audioPackageName(sourceAudioPath)));
    final src = File(sourceAudioPath);
    if (src.path != audio.path) {
      // Drop sibling legacy/new audio so only one canonical file remains.
      for (final name in _audioPackageNames) {
        final sibling = File(_join(dir, name));
        if (sibling.path != audio.path && await sibling.exists()) {
          try {
            await sibling.delete();
          } catch (_) {}
        }
      }
      if (await audio.exists()) await audio.delete();
      try {
        await src.rename(audio.path);
      } catch (_) {
        await src.copy(audio.path);
        try {
          await src.delete();
        } catch (_) {}
      }
    }
    final features = File(_join(dir, 'audio_features.bin'));
    await features.writeAsBytes(timeline.encode(), flush: true);
    return SoundPackagePaths(
      dirPath: dir.path,
      audioPath: audio.path,
      featuresPath: features.path,
      mjpgPath: _join(dir, 'visual.mjpg'),
      idxPath: _join(dir, 'visual.idx'),
      manifestPath: _join(dir, 'visual_manifest.json'),
      coverPath: _join(dir, 'cover.jpg'),
    );
  }

  Future<void> deletePackage(String soundId) async {
    final dir = await packageDir(soundId);
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Rough MJPEG size estimate (bytes) for UI.
  static int estimateVisualBytes({
    required int durationSec,
    int fps = kVisualBakeFps,
    int size = kVisualBakeSize,
    int jpegQuality = kVisualBakeJpegQuality,
  }) {
    // Empirical ~0.8–1.2 KB per 512px frame at q80 particle art
    final perFrame = (size * size * (jpegQuality / 100) * 0.0032).round();
    return (durationSec * fps * perFrame).clamp(0, 200 * 1024 * 1024);
  }
}

class SoundPackagePaths {
  const SoundPackagePaths({
    required this.dirPath,
    required this.audioPath,
    required this.featuresPath,
    required this.mjpgPath,
    required this.idxPath,
    required this.manifestPath,
    required this.coverPath,
  });

  final String dirPath;
  final String audioPath;
  final String featuresPath;
  final String mjpgPath;
  final String idxPath;
  final String manifestPath;
  final String coverPath;
}
