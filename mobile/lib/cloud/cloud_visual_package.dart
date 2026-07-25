import 'dart:io';

import '../data/sound_repository.dart';
import '../visual/audio_feature_timeline.dart';

/// Optional Indexed-MJPEG package attached to Press / cloud upload.
///
/// Multipart field names (alongside required `audio`):
/// - `visual` → visual.mjpg
/// - `visual_idx` → visual.idx
/// - `visual_manifest` → visual_manifest.json
/// - `cover` → cover.jpg
/// - `audio_features` → audio_features.bin
/// - form: `visual_seed`, `renderer_version`
class CloudVisualPackage {
  const CloudVisualPackage({
    this.mjpg,
    this.idx,
    this.manifest,
    this.cover,
    this.features,
    this.visualSeed,
    this.rendererVersion = kSoundVisualRendererVersion,
  });

  final File? mjpg;
  final File? idx;
  final File? manifest;
  final File? cover;
  final File? features;
  final int? visualSeed;
  final String rendererVersion;

  bool get hasFrames =>
      mjpg != null &&
      idx != null &&
      manifest != null &&
      mjpg!.existsSync() &&
      idx!.existsSync() &&
      manifest!.existsSync();

  /// Resolve from a local [SoundMemory] package (null when bake not ready).
  static CloudVisualPackage? fromSound(SoundMemory item) {
    if (!item.hasIndexedVisual) return null;
    final mjpg = _fileIfExists(item.visualMjpgPath);
    final idx = _fileIfExists(item.visualIdxPath);
    final manifest = _fileIfExists(item.visualManifestPath);
    if (mjpg == null || idx == null || manifest == null) return null;
    return CloudVisualPackage(
      mjpg: mjpg,
      idx: idx,
      manifest: manifest,
      cover: _fileIfExists(item.coverPath),
      features: _fileIfExists(item.audioFeaturesPath),
      visualSeed: item.visualSeed,
      rendererVersion: item.rendererVersion,
    );
  }

  static File? _fileIfExists(String? path) {
    if (path == null || path.isEmpty) return null;
    final f = File(path);
    return f.existsSync() ? f : null;
  }
}
