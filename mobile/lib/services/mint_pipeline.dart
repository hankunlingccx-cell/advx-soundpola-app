import 'dart:io';
import 'package:flutter/foundation.dart';
import '../cloud/cloud_media_client.dart';
import '../cloud/cloud_media_models.dart';
import '../cloud/cloud_upload.dart';
import '../data/sound_repository.dart';
import 'auth_service.dart';
import 'chain_client.dart';
import 'nfc_service.dart';
import 'tx_signer_service.dart';
import 'visual_shape_service.dart';

/// 上链管道：分为云阶段（startCloud）和链阶段（startChain）。
///
/// 云阶段：上传 → 云端 READY → cloudReady（NFC 可写入）。
/// 链阶段：cloudReady → 铸造 NFT → chainReady（可选）。
class MintPipeline extends ChangeNotifier {
  MintPipeline._();
  static final MintPipeline instance = MintPipeline._();

  final CloudMediaClient _cloud = CloudMediaClient();
  final ChainClient _chain = ChainClient();
  final Set<String> _running = {};
  final Map<String, String> _errors = {};

  bool isRunning(String soundId) => _running.contains(soundId);
  String? errorOf(String soundId) => _errors[soundId];

  Future<void> retryCloud(String soundId) => startCloud(soundId);
  Future<void> retryChain(String soundId) => startChain(soundId);

  /// Phase 1: 上传到云端，等待 READY，生成 discId。
  Future<void> startCloud(String soundId) async {
    if (_running.contains(soundId)) return;
    final repo = SoundRepository.instance;
    final item = repo.get(soundId);
    if (item == null) return;

    _running.add(soundId);
    _errors.remove(soundId);
    notifyListeners();

    try {
      final token = await AuthService.instance.requireCloudToken();
      final summary = await _ensureCloudReady(item, token);

      final contentId = summary.contentId;
      final discId = NfcService.instance.generateDiscId(contentId);

      String? visualPath;
      if (summary.visualUrl != null && summary.visualUrl!.isNotEmpty) {
        try {
          visualPath = await VisualShapeService.instance.cacheFromUrl(
            contentId: contentId,
            url: summary.visualUrl!,
            token: token,
          );
        } catch (e) {
          debugPrint('visual fetch failed (non-blocking): $e');
        }
      }

      repo.markCloudReady(
        soundId,
        contentId: contentId,
        discId: discId,
        nfcUrl: summary.nfcUrl,
        cloudState: summary.state.wire,
        visualPath: visualPath,
        visualUrl: summary.visualUrl,
      );
    } catch (e) {
      debugPrint('startCloud failed for $soundId: $e');
      _errors[soundId] = e.toString();
      repo.markUploadFailed(soundId);
    } finally {
      _running.remove(soundId);
      notifyListeners();
    }
  }

  /// Phase 2: 铸造 NFT（需要 cloudReady 状态）。
  /// 本地有私钥 → 客户端签名；否则 → 服务端签名。
  Future<void> startChain(String soundId) async {
    if (_running.contains(soundId)) return;
    final repo = SoundRepository.instance;
    final item = repo.get(soundId);
    if (item == null) return;
    if (item.contentId == null || item.contentId!.isEmpty) return;

    _running.add(soundId);
    _errors.remove(soundId);
    notifyListeners();

    try {
      final token = await AuthService.instance.requireCloudToken();
      final contentId = item.contentId!;

      repo.markChainPending(
        soundId,
        contentId: contentId,
        nfcUrl: item.nfcUrl,
        cloudState: item.cloudState,
      );

      final MintResult result;

      // 先看链上状态：已铸造直接落地，铸造中则轮询等待，
      // 避免对已在铸造的内容重复发起 mint 被服务端拒绝。
      final status = await _chain.getChainStatus(
        contentId: contentId,
        token: token,
      );
      if (status.chainState == ChainState.minted) {
        debugPrint('startChain $contentId: already minted, adopting');
        result = _resultFromStatus(contentId, status);
      } else if (status.chainState == ChainState.minting) {
        debugPrint('startChain $contentId: already minting, waiting');
        result = await _waitChainMinted(contentId, token);
      } else {
        result = await _mint(contentId, token);
      }

      repo.markChainReady(
        soundId,
        contentId: contentId,
        chainTokenId: result.tokenId,
        txHash: result.txHash,
        contractAddress: result.contractAddress,
        discId: item.discId,
        nfcUrl: item.nfcUrl,
        cloudState: item.cloudState,
      );
    } catch (e) {
      debugPrint('startChain failed for $soundId: $e');
      _errors[soundId] = e.toString();
      repo.markChainFailed(soundId, item.discId ?? 'SP-UNKNOWN');
    } finally {
      _running.remove(soundId);
      notifyListeners();
    }
  }

  /// 发起铸造：本地有私钥走客户端签名，否则走服务端签名。
  /// 若服务端返回"已在铸造中"（并发或上次未完成），改为轮询等待结果。
  Future<MintResult> _mint(String contentId, String token) async {
    final localKey = await AuthService.instance.readLocalPrivateKey();
    try {
      if (localKey != null && localKey.isNotEmpty) {
        debugPrint('startChain $contentId: client-sign path');
        final unsignedTx = await _chain.prepareMint(
          contentId: contentId,
          token: token,
        );
        final rawTx = await TxSignerService.signTransaction(unsignedTx, localKey);
        return _chain.submitSigned(
          contentId: contentId,
          rawTx: rawTx,
          token: token,
        );
      }
      debugPrint('startChain $contentId: server-sign path');
      return _chain.mintServerSide(contentId: contentId, token: token);
    } on CloudMediaException catch (e) {
      if (e.statusCode == 409 || e.message.contains('铸造中')) {
        debugPrint('startChain $contentId: server reports minting, waiting');
        return _waitChainMinted(contentId, token);
      }
      rethrow;
    }
  }

  /// 轮询链上状态直到 MINTED / FAILED 或超时。
  Future<MintResult> _waitChainMinted(String contentId, String token) async {
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    var delay = const Duration(milliseconds: 800);
    while (DateTime.now().isBefore(deadline)) {
      final status = await _chain.getChainStatus(
        contentId: contentId,
        token: token,
      );
      if (status.chainState == ChainState.minted) {
        return _resultFromStatus(contentId, status);
      }
      if (status.chainState == ChainState.failed) {
        throw CloudMediaException(status.errorMessage ?? '链上铸造失败');
      }
      await Future.delayed(delay);
      if (delay < const Duration(seconds: 4)) {
        delay = Duration(milliseconds: (delay.inMilliseconds * 1.4).round());
      }
    }
    throw CloudMediaException('链上铸造超时，请稍后在 Collection 查看状态');
  }

  MintResult _resultFromStatus(String contentId, ChainStatus status) =>
      MintResult(
        contentId: contentId,
        tokenId: status.tokenId ?? 0,
        txHash: status.txHash ?? '',
        contractAddress: status.contractAddress ?? '',
      );

  /// Claim: 领取他人已上链的内容，铸造新 edition 到自己钱包。
  Future<MintResult> claimContent(String contentId) async {
    final token = await AuthService.instance.requireCloudToken();
    final localKey = await AuthService.instance.readLocalPrivateKey();

    if (localKey != null && localKey.isNotEmpty) {
      final unsignedTx = await _chain.prepareClaim(
        contentId: contentId,
        token: token,
      );
      final rawTx = await TxSignerService.signTransaction(unsignedTx, localKey);
      return _chain.submitClaimSigned(
        contentId: contentId,
        rawTx: rawTx,
        token: token,
      );
    } else {
      return _chain.claimServerSide(
        contentId: contentId,
        token: token,
      );
    }
  }

  Future<ContentSummary> _ensureCloudReady(
    SoundMemory item,
    String token,
  ) async {
    final repo = SoundRepository.instance;
    var contentId = item.contentId;

    if (contentId != null && contentId.isNotEmpty) {
      var summary = await _cloud.getContent(token: token, contentId: contentId);
      if (summary.state == CloudContentState.failed) {
        summary = await _cloud.retryContent(token: token, contentId: contentId);
      }
      // READY 仍可能缺视频：网页 /c 固定播 /preview/.../video，需补传本机 MP4。
      summary = await ensureContentReadyWithVideo(
        cloud: _cloud,
        item: item,
        token: token,
        contentId: contentId,
      );
      if (summary.state == CloudContentState.ready) return summary;
      return _cloud.waitUntilReady(token: token, contentId: contentId);
    }

    final path = item.audioPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      throw StateError('缺少本地录音文件，无法上传云端');
    }

    repo.markUploading(item.id);
    final created = await uploadSoundPackage(
      cloud: _cloud,
      item: item,
      token: token,
    );
    contentId = created.contentId;
    repo.markContentUploaded(
      item.id,
      contentId,
      cloudState: created.state.wire,
    );

    if (created.state == CloudContentState.ready) {
      return _cloud.getContent(token: token, contentId: contentId);
    }
    return _cloud.waitUntilReady(token: token, contentId: contentId);
  }
}
