import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/sound_repository.dart';
import '../visual/visual_bake_service.dart';
import '../visual/visual_mp4_exporter.dart';
import 'cloud_media_client.dart';
import 'cloud_media_models.dart';

/// Press / cloud: audio first, then on-device visualization MP4.
///
/// 1. Wait for Indexed-MJPEG bake
/// 2. `POST /api/v1/contents` field `audio` → `content_id`
/// 3. Encode bake → H.264 `visual.mp4`
/// 4. `POST /api/v1/contents/{id}/video` field `video` → typically `READY`
Future<ContentCreated> uploadSoundPackage({
  required CloudMediaClient cloud,
  required SoundMemory item,
  required String token,
  void Function(String status)? onStatus,
}) async {
  onStatus?.call('正在准备可视化帧序列…');
  final baked =
      await VisualBakeService.instance.ensureReady(item.id) ?? item;

  final path = baked.audioPath ?? item.audioPath;
  if (path == null || path.isEmpty || !File(path).existsSync()) {
    throw StateError('缺少本地录音文件，无法上传云端');
  }

  onStatus?.call('正在上传音频到云端…');
  final created = await cloud.uploadAudio(
    token: token,
    file: File(path),
    filename: path.split(Platform.pathSeparator).last,
  );

  if (!baked.hasIndexedVisual) {
    debugPrint(
      '[CloudUpload] sound ${item.id}: bake not ready '
      '(${baked.visualBakeStatus.name}); audio-only upload',
    );
    return created;
  }

  onStatus?.call('正在导出可视化视频…');
  final mp4 = await VisualMp4Exporter.instance.export(baked);
  if (mp4 == null) {
    debugPrint(
      '[CloudUpload] sound ${item.id}: MP4 export failed; audio-only',
    );
    return created;
  }

  onStatus?.call('正在上传可视化视频…');
  try {
    final video = await cloud.uploadVideo(
      token: token,
      contentId: created.contentId,
      file: mp4,
    );
    debugPrint(
      '[CloudUpload] video uploaded content=${video.contentId} '
      'state=${video.state.wire} sha=${video.videoSha256}',
    );
    // Promote to READY when the video endpoint says so, so callers can skip poll.
    if (video.state == CloudContentState.ready) {
      return ContentCreated(
        contentId: created.contentId,
        state: CloudContentState.ready,
        displayLabel: created.displayLabel,
        statusUrl: created.statusUrl,
      );
    }
  } catch (e) {
    debugPrint('[CloudUpload] video upload failed (non-fatal): $e');
  }
  return created;
}
