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

/// Clip user title for Cloud Media `display_label` (1–64 chars).
String? cloudDisplayLabelOf(SoundMemory item) {
  final t = item.title.trim();
  if (t.isEmpty) return null;
  return t.length > 64 ? t.substring(0, 64) : t;
}

/// Multipart `audio` filename: user sound title + original extension.
///
/// Falls back to the on-disk basename when the title is empty / unusable.
String cloudAudioFilenameOf(SoundMemory item, String audioPath) {
  final fallback = audioPath.split(Platform.pathSeparator).last;
  final dot = fallback.lastIndexOf('.');
  final ext = (dot > 0 && dot < fallback.length - 1)
      ? fallback.substring(dot)
      : '.wav';

  final label = cloudDisplayLabelOf(item);
  if (label == null) return fallback;

  final safe = label
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  if (safe.isEmpty) return fallback;

  // Keep room for extension; many FS / proxies cap near 255 bytes.
  final maxStem = 200 - ext.length;
  final stem = safe.length > maxStem ? safe.substring(0, maxStem).trim() : safe;
  if (stem.isEmpty) return fallback;
  return '$stem$ext';
}

/// Push local sound name to cloud so NFC `/c/{id}` page shows it
/// (server default is「声音碎片 #XXXX」).
Future<ContentSummary?> syncCloudDisplayLabel({
  required CloudMediaClient cloud,
  required SoundMemory item,
  required String token,
  required String contentId,
  void Function(String status)? onStatus,
}) async {
  final label = cloudDisplayLabelOf(item);
  if (label == null) return null;
  onStatus?.call('正在同步声音名称…');
  try {
    final summary = await cloud.renameContent(
      token: token,
      contentId: contentId,
      displayLabel: label,
    );
    debugPrint(
      '[CloudUpload] sound ${item.id}: display_label="$label"',
    );
    return summary;
  } catch (e) {
    debugPrint('[CloudUpload] sound ${item.id}: rename failed: $e');
    return null;
  }
}

/// If [item] has a local `visual.mp4`, POST it to an existing content.
///
/// Returns the video response when upload ran; null when skipped / failed soft.
/// Safe to call even when content is already READY (audio-only READY was
/// skipping this path and left `/preview/{id}/video` 404 for the NFC web page).
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

/// Bake if needed, then attach local MP4 even when the content is already READY.
Future<ContentSummary> ensureContentReadyWithVideo({
  required CloudMediaClient cloud,
  required SoundMemory item,
  required String token,
  required String contentId,
  void Function(String status)? onStatus,
}) async {
  final baked =
      await VisualBakeService.instance.ensureReady(item.id) ?? item;
  await attachVisualVideoIfNeeded(
    cloud: cloud,
    item: baked,
    token: token,
    contentId: contentId,
    onStatus: onStatus,
  );
  final renamed = await syncCloudDisplayLabel(
    cloud: cloud,
    item: baked,
    token: token,
    contentId: contentId,
    onStatus: onStatus,
  );
  return renamed ??
      await cloud.getContent(token: token, contentId: contentId);
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
  final audioFilename = cloudAudioFilenameOf(baked, path);
  final created = await cloud.uploadAudio(
    token: token,
    file: File(path),
    filename: audioFilename,
  );

  final video = await attachVisualVideoIfNeeded(
    cloud: cloud,
    item: baked,
    token: token,
    contentId: created.contentId,
    onStatus: onStatus,
  );

  final renamed = await syncCloudDisplayLabel(
    cloud: cloud,
    item: baked,
    token: token,
    contentId: created.contentId,
    onStatus: onStatus,
  );

  if (video == null) {
    debugPrint(
      '[CloudUpload] sound ${item.id}: no visual.mp4; audio-only '
      '(state=${created.state.wire}) — NFC web /preview/.../video will 404',
    );
    return ContentCreated(
      contentId: created.contentId,
      state: created.state,
      displayLabel: renamed?.displayLabel ?? created.displayLabel,
      statusUrl: created.statusUrl,
    );
  }

  return ContentCreated(
    contentId:
        video.contentId.isNotEmpty ? video.contentId : created.contentId,
    state: video.state,
    displayLabel: renamed?.displayLabel ?? created.displayLabel,
    statusUrl: created.statusUrl,
  );
}
