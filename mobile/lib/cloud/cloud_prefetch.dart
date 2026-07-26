import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/sound_repository.dart';
import '../services/auth_service.dart';
import '../visual/audio_feature_timeline.dart';
import 'cloud_media_client.dart';
import 'cloud_media_config.dart';
import 'cloud_media_models.dart';
import 'cloud_upload.dart';

/// 录音可视化就绪后后台预上传云端，缩短 Press／NFC 写入等待。
///
/// 流程：音频 → `content_id`，再尽量上传本机 `visual.mp4`；只写入
/// `contentId`／`nfcUrl`／`cloudState`，不改变 Draft 的 `SoundStatus`
///（避免误标为 writing／cloudReady 导致无法拖入写入机）。
///
/// 注意：云端可在仅音频时就标 READY；若因此跳过 MP4，NFC 网页
/// `/c/{id}` 的 `<video src=/preview/.../video>` 会 404。故 READY 后仍会
/// 在本机会话内补传一次本地 `visual.mp4`。
class CloudPrefetchService {
  CloudPrefetchService._();
  static final CloudPrefetchService instance = CloudPrefetchService._();

  final CloudMediaClient _cloud = CloudMediaClient();
  final Set<String> _inflight = {};
  /// Per-session: one video-attach attempt for already-READY contents.
  final Set<String> _videoAttachTried = {};

  /// 单条：bake 完成后或保存 Draft 时调用。
  void schedule(String soundId) {
    unawaited(prefetch(soundId));
  }

  /// 启动／登录后：补传尚未就绪的 Draft。
  Future<void> prefetchPendingDrafts() async {
    if (!AuthService.instance.isLoggedIn) return;
    for (final draft in SoundRepository.instance.drafts) {
      if (_needsPrefetch(draft)) schedule(draft.id);
    }
  }

  bool _needsPrefetch(SoundMemory item) {
    if (item.status == SoundStatus.collected) return false;
    if (_isLocallyReady(item)) return false;

    final baking = item.visualBakeStatus == VisualBakeStatus.processingVisual ||
        item.visualBakeStatus == VisualBakeStatus.indexing;
    if (baking) return false;

    // 等可视化 bake 就绪再传（便于附带 MP4）；bake 失败则仍可仅传音频。
    if (!item.hasIndexedVisual &&
        item.visualBakeStatus != VisualBakeStatus.failed &&
        item.visualBakeStatus != VisualBakeStatus.ready) {
      return false;
    }

    final path = item.audioPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return false;
    }
    return true;
  }

  bool _isLocallyReady(SoundMemory item) {
    final cid = item.contentId?.trim() ?? '';
    if (cid.isEmpty) return false;
    final state = (item.cloudState ?? '').toUpperCase();
    if (state != 'READY') return false;
    // READY but local MP4 not yet offered → NFC web page has no video.
    if (item.hasVisualMp4 && !_videoAttachTried.contains(item.id)) {
      return false;
    }
    return true;
  }

  Future<void> prefetch(String soundId) async {
    if (_inflight.contains(soundId)) return;
    if (!AuthService.instance.isLoggedIn || !AuthService.instance.hasCloudToken) {
      return;
    }

    final repo = SoundRepository.instance;
    var item = repo.get(soundId);
    if (item == null || !_needsPrefetch(item)) return;

    _inflight.add(soundId);
    debugPrint('[CloudPrefetch] start $soundId');
    try {
      final token = await AuthService.instance.requireCloudToken();
      await _cloud.assertReachable();
      item = repo.get(soundId);
      if (item == null) return;

      final ready = await _ensureReadyQuiet(item, token);
      final contentId = ready.contentId.trim();
      if (contentId.isEmpty) return;

      final nfcUrl = ready.nfcUrl?.trim();
      final writeUrl = (nfcUrl != null && nfcUrl.isNotEmpty)
          ? nfcUrl
          : '${CloudMediaConfig.baseUrl}/c/$contentId';

      // 仅补云端字段；若用户已开始 Press 改成 writing 等，也一并保留。
      repo.update(
        soundId,
        (s) => s.copyWith(
          contentId: contentId,
          nfcUrl: writeUrl,
          cloudState: ready.state.wire,
        ),
      );
      debugPrint(
        '[CloudPrefetch] ready $soundId contentId=$contentId state=${ready.state.wire}',
      );
    } catch (e) {
      debugPrint('[CloudPrefetch] $soundId failed: $e');
    } finally {
      _inflight.remove(soundId);
    }
  }

  Future<ContentSummary> _ensureReadyQuiet(
    SoundMemory item,
    String token,
  ) async {
    var contentId = item.contentId?.trim();

    if (contentId != null && contentId.isNotEmpty) {
      var summary = await _cloud.getContent(token: token, contentId: contentId);
      if (summary.state == CloudContentState.failed) {
        summary = await _cloud.retryContent(token: token, contentId: contentId);
      }

      // Attach local MP4 even when already READY (audio-only READY left web
      // `/preview/.../video` empty).
      if (item.hasVisualMp4 || summary.state != CloudContentState.ready) {
        _videoAttachTried.add(item.id);
        summary = await ensureContentReadyWithVideo(
          cloud: _cloud,
          item: item,
          token: token,
          contentId: contentId,
        );
        if (summary.state == CloudContentState.ready) return summary;
        return _cloud.waitUntilReady(token: token, contentId: contentId);
      }

      return summary;
    }

    final created = await uploadSoundPackage(
      cloud: _cloud,
      item: item,
      token: token,
    );
    contentId = created.contentId;
    _videoAttachTried.add(item.id);
    SoundRepository.instance.update(
      item.id,
      (s) => s.copyWith(
        contentId: contentId,
        cloudState: created.state.wire,
      ),
    );

    if (created.state == CloudContentState.ready) {
      return _cloud.getContent(token: token, contentId: contentId);
    }
    return _cloud.waitUntilReady(token: token, contentId: contentId);
  }
}
