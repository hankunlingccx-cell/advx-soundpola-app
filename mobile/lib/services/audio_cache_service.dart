import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../cloud/cloud_media_client.dart';
import '../cloud/cloud_media_models.dart';
import '../data/sound_repository.dart';
import 'auth_service.dart';

/// Ensures a [SoundMemory] has a playable local audio file.
///
/// Prefer existing [SoundMemory.audioPath]; otherwise download the cloud
/// playback asset (`GET .../contents/{id}/assets/audio`) into app cache and
/// write the path back onto the memory.
class AudioCacheService {
  AudioCacheService._();
  static final AudioCacheService instance = AudioCacheService._();

  final CloudMediaClient _cloud = CloudMediaClient();
  final _inflight = <String, Future<String?>>{};

  Future<String> _cacheDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/cloud_audio');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  /// Returns a local file path ready for playback / Lab mix, or null.
  Future<String?> ensureLocalAudio(
    SoundMemory sound, {
    String? token,
  }) async {
    final existing = sound.audioPath?.trim();
    if (existing != null &&
        existing.isNotEmpty &&
        File(existing).existsSync()) {
      return existing;
    }

    final contentId = sound.contentId?.trim();
    if (contentId == null || contentId.isEmpty) return null;

    final auth = token ?? AuthService.instance.cloudToken;
    if (auth == null || auth.isEmpty) return null;

    return _inflight.putIfAbsent(contentId, () async {
      try {
        final dir = await _cacheDir();
        final dest = File('$dir/audio_$contentId.mp3');
        if (await dest.exists() && await dest.length() > 0) {
          _persistPath(sound.id, dest.path);
          return dest.path;
        }

        await _cloud.downloadAsset(
          token: auth,
          contentId: contentId,
          assetKind: 'audio',
          dest: dest,
        );
        if (!await dest.exists() || await dest.length() <= 0) return null;
        _persistPath(sound.id, dest.path);
        return dest.path;
      } on CloudMediaException catch (e) {
        debugPrint(
          '[AudioCache] download $contentId failed: ${e.message} (${e.statusCode})',
        );
        return null;
      } catch (e) {
        debugPrint('[AudioCache] download $contentId failed: $e');
        return null;
      } finally {
        _inflight.remove(contentId);
      }
    });
  }

  void _persistPath(String soundId, String path) {
    final cur = SoundRepository.instance.get(soundId);
    if (cur == null) return;
    if (cur.audioPath == path) return;
    SoundRepository.instance.update(
      soundId,
      (s) => s.copyWith(audioPath: path),
    );
  }
}
