import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/sound_repository.dart';
import '../visual/visual_bake_service.dart';
import 'cloud_media_client.dart';
import 'cloud_media_models.dart';

File? _mp4FileOf(SoundMemory item) {
  final path = item.visualMp4Path;
  if (path == null || path.isEmpty) return null;
  final f = File(path);
  if (!f.existsSync()) return null;
  return f;
}

/// If [item] has a local `visual.mp4`, POST it to an existing content.
///
/// Returns the video response when upload ran; null when skipped / failed soft.
Future<ContentVideoUploaded?> attachVisualVideoIfNeeded({
  required CloudMediaClient cloud,
  required SoundMemory item,
  required String token,
  required String contentId,
  void Function(String status)? onStatus,
}) async {
  final mp4 = _mp4FileOf(item);
  if (mp4 == null || await mp4.length() <= 0) return null;

  onStatus?.call('正在上传可视化视频…');
  try {
    final video = await cloud.uploadVideo(
      token: token,
      contentId: contentId,
      file: mp4,
      filename: 'visualization.mp4',
    );
    debugPrint(
      '[CloudUpload] sound ${item.id}: attached video '
      'state=${video.state.wire}',
    );
    return video;
  } catch (e) {
    debugPrint('[CloudUpload] sound ${item.id}: attach video failed: $e');
    return null;
  }
}

/// Two-step cloud upload: audio → `content_id`, then MP4 video → READY.
Future<ContentCreated> uploadSoundPackage({
  required CloudMediaClient cloud,
  required SoundMemory item,
  required String token,
  void Function(String status)? onStatus,
}) async {
  onStatus?.call('正在准备可视化…');
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

  final video = await attachVisualVideoIfNeeded(
    cloud: cloud,
    item: baked,
    token: token,
    contentId: created.contentId,
    onStatus: onStatus,
  );
  if (video == null) {
    debugPrint(
      '[CloudUpload] sound ${item.id}: no visual.mp4; audio-only '
      '(state=${created.state.wire})',
    );
    return created;
  }

  return ContentCreated(
    contentId:
        video.contentId.isNotEmpty ? video.contentId : created.contentId,
    state: video.state,
    displayLabel: created.displayLabel,
    statusUrl: created.statusUrl,
  );
}
