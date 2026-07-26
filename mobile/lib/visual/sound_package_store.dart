import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'audio_feature_timeline.dart';

/// On-disk layout for one sound memory package:
/// ```
/// sounds/{id}/
///   audio.wav | audio.m4a   (new recordings are PCM16 WAV)
///   visual.mjpg
///   visual.idx
///   visual_manifest.json
///   visual.mp4              (H.264 for cloud upload / preview)
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

  /// Prefer WAV (PCM analysis pipeline); fall back to legacy AAC.
  Future<File> audioFile(String soundId) async {
    final dir = await packageDir(soundId);
    final wav = File(_join(dir, 'audio.wav'));
    if (await wav.exists()) return wav;
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

  Future<File> mp4File(String soundId) async =>
      File(_join(await packageDir(soundId), 'visual.mp4'));

  Future<String> packagePath(String soundId) async =>
      (await packageDir(soundId)).path;

  static String _audioPackageName(String sourcePath) {
    final lower = sourcePath.toLowerCase();
    if (lower.endsWith('.wav')) return 'audio.wav';
    return 'audio.m4a';
  }

  /// Copy/move [sourceAudio] into package as audio.wav / audio.m4a; write features.
  ///
  /// When [moveAudio] is false (early prepare after record), keep the source file
  /// so result-page preview / re-record still work until the user commits.
  Future<SoundPackagePaths> materialize({
    required String soundId,
    required String sourceAudioPath,
    required AudioFeatureTimeline timeline,
    bool moveAudio = true,
  }) async {
    final dir = await packageDir(soundId);
    final audio = File(_join(dir, _audioPackageName(sourceAudioPath)));
    final src = File(sourceAudioPath);
    if (src.path != audio.path) {
      // Drop sibling legacy/new audio so only one canonical file remains.
      for (final name in ['audio.wav', 'audio.m4a']) {
        final sibling = File(_join(dir, name));
        if (sibling.path != audio.path && await sibling.exists()) {
          try {
            await sibling.delete();
          } catch (_) {}
        }
      }
      if (await audio.exists()) await audio.delete();
      if (moveAudio) {
        try {
          await src.rename(audio.path);
        } catch (_) {
          await src.copy(audio.path);
          try {
            await src.delete();
          } catch (_) {}
        }
      } else {
        await src.copy(audio.path);
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
      mp4Path: _join(dir, 'visual.mp4'),
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
    this.mp4Path,
  });

  final String dirPath;
  final String audioPath;
  final String featuresPath;
  final String mjpgPath;
  final String idxPath;
  final String manifestPath;
  final String coverPath;
  final String? mp4Path;
}
