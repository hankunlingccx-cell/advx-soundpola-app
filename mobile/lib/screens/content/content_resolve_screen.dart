import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../cloud/cloud_media_client.dart';
import '../../cloud/cloud_media_models.dart';
import '../../data/sound_repository.dart';
import '../../router/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/chain_client.dart';
import '../../services/deep_link_service.dart';
import '../../services/mint_pipeline.dart';
import '../../theme/app_colors.dart';
import '../../widgets/design_components.dart';

class ContentResolveScreen extends StatefulWidget {
  const ContentResolveScreen({super.key, required this.contentId});

  final String contentId;

  @override
  State<ContentResolveScreen> createState() => _ContentResolveScreenState();
}

class _ContentResolveScreenState extends State<ContentResolveScreen> {
  String? _error;
  ChainStatus? _chainStatus;
  ContentSummary? _summary;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    final repo = SoundRepository.instance;

    final local = repo.findByContentId(widget.contentId);
    if (local != null) {
      _goMemory(local.id);
      return;
    }

    if (!AuthService.instance.isLoggedIn) {
      PendingDeepLink.set(widget.contentId);
      if (mounted) context.go(AppRoutes.login);
      return;
    }

    try {
      final token = await AuthService.instance.requireCloudToken();
      final cloud = CloudMediaClient();
      final chain = ChainClient();

      final summary = await cloud.getContent(
        token: token,
        contentId: widget.contentId,
      );

      ChainStatus chainStatus;
      try {
        chainStatus = await chain.getChainStatus(
          contentId: widget.contentId,
          token: token,
        );
      } catch (_) {
        chainStatus = ChainStatus(
          contentId: widget.contentId,
          chainState: ChainState.none,
        );
      }

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _chainStatus = chainStatus;
      });

      if (chainStatus.chainState != ChainState.minted) {
        return;
      }

      final editions = await chain.getEditions(
        contentId: widget.contentId,
        token: token,
      );
      final myWallet = AuthService.instance.currentUser?.walletAddress;
      final alreadyClaimed = myWallet != null &&
          editions.editions.any(
            (e) => e.ownerWallet.toLowerCase() == myWallet.toLowerCase(),
          );

      if (alreadyClaimed) {
        repo.syncCloudCollection([summary]);
        final found = repo.findByContentId(widget.contentId);
        if (found != null) {
          _goMemory(found.id);
          return;
        }
      }

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败，请稍后重试');
    }
  }

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      await MintPipeline.instance.claimContent(widget.contentId);
      final token = await AuthService.instance.requireCloudToken();
      final summary = _summary ??
          await CloudMediaClient().getContent(
            token: token,
            contentId: widget.contentId,
          );
      SoundRepository.instance.syncCloudCollection([summary]);
      final found = SoundRepository.instance.findByContentId(widget.contentId);
      if (found != null) {
        _goMemory(found.id);
      } else if (mounted) {
        setState(() => _error = '保存成功，但未能打开详情');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  void _goMemory(String id) {
    if (!mounted) return;
    context.pushReplacement(AppRoutes.memoryPath(id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => context.go(AppRoutes.main),
                child: const Text('返回首页'),
              ),
            ],
          ),
        ),
      );
    }

    if (_summary == null) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF63E0CB),
          ),
        ),
      );
    }

    final isMinted = _chainStatus?.chainState == ChainState.minted;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isMinted
                    ? AppColors.accent.withValues(alpha: 0.15)
                    : AppColors.surface2,
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(
                isMinted ? '已上链' : '仅预览 · 未上链',
                style: TextStyle(
                  color: isMinted ? AppColors.accent : AppColors.textTertiary,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _summary!.displayLabel.isNotEmpty
                  ? _summary!.displayLabel
                  : '声音碎片',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${((_summary!.durationMs ?? 0) / 1000).round()}s',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            if (isMinted)
              PrimaryButton(
                text: _claiming ? '保存中...' : '保存到我的账户',
                enabled: !_claiming,
                onPressed: _claiming ? null : _claim,
              )
            else
              SecondaryButton(
                text: '返回首页',
                onPressed: () => context.go(AppRoutes.main),
              ),
            if (isMinted) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go(AppRoutes.main),
                child: const Text(
                  '稍后再说',
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
