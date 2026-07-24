import 'package:flutter/material.dart';
import '../../cloud/cloud_media_client.dart';
import '../../data/sound_repository.dart';
import '../../services/audio_playback_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/sound_visual.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({
    super.key,
    required this.onOpenMemory,
    required this.onLogin,
  });

  final ValueChanged<String> onOpenMemory;
  final VoidCallback onLogin;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final _cloud = CloudMediaClient();
  bool _syncing = false;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChanged);
    _maybeSync();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    _cloud.close();
    super.dispose();
  }

  void _onAuthChanged() {
    _maybeSync();
    if (mounted) setState(() {});
  }

  Future<void> _maybeSync() async {
    if (!AuthService.instance.isLoggedIn || _syncing) return;
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      final token = await AuthService.instance.requireCloudToken();
      final list = await _cloud.listContents(token);
      SoundRepository.instance.syncCloudCollection(list.items);
    } catch (e) {
      if (mounted) {
        setState(() => _syncError = e.toString());
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        SoundRepository.instance,
        AuthService.instance,
      ]),
      builder: (context, _) {
        final loggedIn = AuthService.instance.isLoggedIn;
        final items = SoundRepository.instance.collection;
        return ColoredBox(
          color: AppColors.bgPrimary,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: 'Collection',
                  subtitle: loggedIn
                      ? (_syncing
                          ? '同步云端收藏…'
                          : '${items.length} 段收藏')
                      : '数字收藏',
                ),
                if (loggedIn && _syncError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.pageHorizontal,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '云端同步失败：$_syncError',
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _syncing ? null : _maybeSync,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: !loggedIn
                      ? _LoginGate(onLogin: widget.onLogin)
                      : items.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(
                                  AppSpacing.pageHorizontal,
                                ),
                                child: Text(
                                  _syncing
                                      ? '正在从云端加载…'
                                      : '还没有收藏的声音\n从 Drafts 写入第一张声片吧',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _maybeSync,
                              color: AppColors.accent,
                              child: GridView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.pageHorizontal,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: AppSpacing.tight,
                                  mainAxisSpacing: AppSpacing.tight,
                                  childAspectRatio: 0.72,
                                ),
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return _CollectionCard(
                                    item: item,
                                    onTap: () => widget.onOpenMemory(item.id),
                                  );
                                },
                              ),
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LoginGate extends StatelessWidget {
  const _LoginGate({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              height: 140,
              width: 140,
              child: SoundVisualCanvas(seed: 9090, active: false),
            ),
            const SizedBox(height: AppSpacing.item),
            const Text(
              '登录后查看数字收藏',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '已写入声片并完成上链的声音会出现在这里。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.section),
            PrimaryButton(text: '登录', onPressed: onLogin),
          ],
        ),
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.item, required this.onTap});
  final SoundMemory item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(AppRadii.collectionCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: ColoredBox(
                color: AppColors.surface2,
                child: Stack(
                  children: [
                    SoundVisualCanvas(
                      seed: item.visualSeed,
                      mode: SoundVisualMode.complete,
                    ),
                    if (item.discId != null)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.bgPrimary.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.45),
                            ),
                          ),
                          child: const Text(
                            '声片',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.category} · ${item.locationLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, required this.id, required this.onBack});

  final String id;
  final VoidCallback onBack;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  bool _playing = false;
  bool _assetExpanded = false;
  final _player = AudioPlaybackService.instance;

  @override
  void dispose() {
    _player.stop();
    super.dispose();
  }

  Future<void> _togglePlay(String? path) async {
    if (path == null || path.isEmpty) {
      setState(() => _playing = !_playing);
      return;
    }
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
    } else {
      await _player.play(path);
      setState(() => _playing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SoundRepository.instance,
      builder: (context, _) {
        final item = SoundRepository.instance.get(widget.id);
        if (item == null) {
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: widget.onBack,
                child: const Text('返回'),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageHorizontal,
              ),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: widget.onBack,
                      child: const Text(
                        '返回',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    const Text(
                      'Memory',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '分享',
                      style: TextStyle(
                        color: AppColors.textTertiary.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.tight),
                Text(
                  formatRecordedAt(item.recordedAt),
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
                Text(
                  item.locationLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: AppSpacing.item),
                GestureDetector(
                  onTap: () => _togglePlay(item.audioPath),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(AppRadii.collectionCard),
                    child: SizedBox(
                      height: 340,
                      child: ColoredBox(
                        color: AppColors.surface1,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.section),
                          child: SoundVisualCanvas(
                            seed: item.visualSeed,
                            mode: _playing
                                ? SoundVisualMode.playback
                                : SoundVisualMode.complete,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.section),
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '#${item.category}  ·  ${formatDuration(item.durationSec)}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                StatusChip(status: item.status),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.item),
                  Text(
                    item.description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.section),
                InkWell(
                  onTap: () =>
                      setState(() => _assetExpanded = !_assetExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.tight,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '声片与数字资产',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          _assetExpanded ? '收起' : '展开',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_assetExpanded) ...[
                  MetaRow(label: '声片编号', value: item.discId ?? '—'),
                  MetaRow(
                    label: '写入时间',
                    value: item.pressedAt != null
                        ? formatRecordedAt(item.pressedAt!)
                        : '—',
                  ),
                  MetaRow(label: '数字资产编号', value: item.assetId ?? '—'),
                  MetaRow(
                    label: '上链时间',
                    value: item.chainedAt != null
                        ? formatRecordedAt(item.chainedAt!)
                        : '—',
                  ),
                  const MetaRow(label: '绑定状态', value: '永久绑定'),
                  MetaRow(label: '网络', value: item.networkLabel),
                  MetaRow(label: '合约', value: item.contractLabel ?? '—'),
                  MetaRow(label: 'Token ID', value: item.tokenId ?? '—'),
                  MetaRow(label: '交易凭证', value: item.txHash ?? '—'),
                ],
                const SizedBox(height: AppSpacing.section),
              ],
            ),
          ),
        );
      },
    );
  }
}
