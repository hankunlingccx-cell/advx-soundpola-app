import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/sound_repository.dart';
import '../visual/visual_bake_service.dart';
import 'cloud_media_client.dart';
import 'cloud_media_models.dart';
import 'cloud_visual_package.dart';

/// Wait for local Indexed-MJPEG bake, then upload audio + visual package.
Future<ContentCreated> uploadSoundPackage({
  required CloudMediaClient cloud,
  required SoundMemory item,
  required String token,
  void Function(String status)? onStatus,
}) async {
  onStatus?.call('正在准备可视化帧序列…');
  final baked =
      await VisualBakeService.instance.ensureReady(item.id) ?? item;
  final visual = CloudVisualPackage.fromSound(baked);
  if (visual == null) {
    debugPrint(
      '[CloudUpload] sound ${item.id}: bake not ready '
      '(${baked.visualBakeStatus.name}); uploading audio only',
    );
  } else {
    debugPrint(
      '[CloudUpload] sound ${item.id}: attaching Indexed-MJPEG package',
    );
  }

  final path = baked.audioPath ?? item.audioPath;
  if (path == null || path.isEmpty || !File(path).existsSync()) {
    throw StateError('缺少本地录音文件，无法上传云端');
  }

  onStatus?.call(
    visual != null ? '正在上传音频与可视化帧序列…' : '正在上传音频到云端…',
  );
  return cloud.uploadAudio(
    token: token,
    file: File(path),
    filename: path.split(Platform.pathSeparator).last,
    visual: visual,
  );
}
