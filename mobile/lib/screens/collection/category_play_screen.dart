import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/sound_repository.dart';
import '../../services/audio_playback_service.dart';
import '../../services/location_capture_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/empty_state_panel.dart';
import '../../widgets/indexed_visual_player.dart';
import '../../widgets/sound_nft_card.dart';
import '../../widgets/sound_visual.dart';
import '../../widgets/sp_category_picker.dart';
import 'disc_stack_carousel.dart';

/// 声片分类播放页：浏览 + 播放可视化主体 + 贴图堆叠 + 完整记忆。
/// 不再跳转独立 Memory 详情页。
String _chainStatusLabel(SoundStatus status) {
  switch (status) {
    case SoundStatus.collected:
      return '已上链';
    case SoundStatus.chainPending:
      return '上链中';
    case SoundStatus.chainFailed:
      return '上链失败，可重试';
    default:
      return '—';
  }
}

class CategoryPlayScreen extends StatefulWidget {
  const CategoryPlayScreen({
    super.key,
    required this.category,
    this.initialSoundId,
    required this.onBack,
  });

  final String category;
  final String? initialSoundId;
  final VoidCallback onBack;

  @override
  State<CategoryPlayScreen> createState() => _CategoryPlayScreenState();
}

class _CategoryPlayScreenState extends State<CategoryPlayScreen> {
  final _player = AudioPlaybackService.instance;

  late List<SoundMemory> _items;
  late int _index;
  bool _wasPlayingBeforeSwitch = false;

  /// 无真实文件时的模拟播放（演示收藏数据）。
  Timer? _simTimer;
  bool _simPlaying = false;
  double _simProgress = 0;
  final ValueNotifier<int> _positionMs = ValueNotifier(0);

  SoundMemory? get _current =>
      _items.isEmpty ? null : _items[_index.clamp(0, _items.length - 1)];

  bool get _playing {
    final item = _current;
    if (item == null) return false;
    final path = item.audioPath;
    if (path != null && path.isNotEmpty) {
      return _player.isPlaying && _player.currentPath == path;
    }
    return _simPlaying;
  }

  double get _progress {
    final item = _current;
    if (item == null) return 0;
    final path = item.audioPath;
    if (path != null && path.isNotEmpty && _player.currentPath == path) {
      return _player.progress;
    }
    return _simProgress;
  }

  @override
  void initState() {
    super.initState();
    _reloadItems();
    _player.addListener(_onPlayerChanged);
    SoundRepository.instance.addListener(_onRepoChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetchNeighbors(_index);
    });
  }

  void _onRepoChanged() {
    if (!mounted) return;
    _reloadItems();
    setState(() {});
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    _player.removeListener(_onPlayerChanged);
    SoundRepository.instance.removeListener(_onRepoChanged);
    _positionMs.dispose();
    _player.softStop();
    super.dispose();
  }

  void _reloadItems() {
    final groups = SoundRepository.instance.collectionGroups;
    CollectionGroup? group;
    for (final g in groups) {
      if (g.category == widget.category) {
        group = g;
        break;
      }
    }
    _items = group?.items ?? const [];
    if (_items.isEmpty) {
      _index = 0;
      return;
    }
    final initialId = widget.initialSoundId;
    final found = initialId == null
        ? -1
        : _items.indexWhere((s) => s.id == initialId);
    _index = found >= 0 ? found : 0;
  }

  /// 播放到结尾时把环形进度归零，而非停留在满环。
  void _onPlayerChanged() {
    if (!mounted) return;
    final item = _current;
    final path = item?.audioPath;
    if (path != null &&
        path.isNotEmpty &&
        _player.currentPath == path) {
      _positionMs.value = _player.position.inMilliseconds;
    }
    final justFinished = path != null &&
        path.isNotEmpty &&
        _player.currentPath == path &&
        !_player.isPlaying &&
        _player.error == null &&
        _player.duration.inMilliseconds > 0 &&
        _player.position >= _player.duration;
    if (justFinished) {
      _player.softStop();
      return;
    }
    setState(() {});
  }

  Future<void> _onIndexChanged(int index) async {
    if (index == _index || index < 0 || index >= _items.length) return;

    final keepPlaying = _playing || _wasPlayingBeforeSwitch;
    _wasPlayingBeforeSwitch = keepPlaying;

    setState(() {
      _index = index;
      _simProgress = 0;
      _simPlaying = false;
    });
    _simTimer?.cancel();

    // 切换：先停当前，再载入新声音（禁止重叠）
    await _player.softStop();

    if (!mounted) return;
    _prefetchNeighbors(index);

    if (keepPlaying) {
      _wasPlayingBeforeSwitch = false;
      await _startPlayback();
    }
  }

  void _prefetchNeighbors(int index) {
    // 预热相邻声片元数据，便于后续扩展音频/视觉资源缓存
    for (final i in [index - 1, index, index + 1]) {
      if (i < 0 || i >= _items.length) continue;
      _items[i].visualSeed;
      _items[i].audioPath;
    }
  }

  Future<void> _togglePlay() async {
    HapticFeedback.selectionClick();
    if (_playing) {
      await _pausePlayback();
    } else {
      await _startPlayback();
    }
  }

  Future<void> _startPlayback() async {
    final item = _current;
    if (item == null) return;

    final path = item.audioPath;
    if (path != null && path.isNotEmpty) {
      await _player.playExclusive(path);
      if (mounted) setState(() {});
      return;
    }

    // 演示数据：无本地文件时模拟进度
    _simTimer?.cancel();
    setState(() {
      _simPlaying = true;
      if (_simProgress >= 0.99) _simProgress = 0;
    });
    final totalMs = math.max(item.durationSec, 1) * 1000;
    _simTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _simProgress += 50 / totalMs;
        if (_simProgress >= 1) {
          // 结尾归零，而非停留在满环
          _simProgress = 0;
          _simPlaying = false;
          t.cancel();
        }
      });
    });
  }

  Future<void> _pausePlayback() async {
    final item = _current;
    if (item == null) return;
    final path = item.audioPath;
    if (path != null && path.isNotEmpty) {
      await _player.pause();
    } else {
      _simTimer?.cancel();
      setState(() => _simPlaying = false);
    }
  }

  Future<void> _editTitle(SoundMemory item) async {
    final controller = TextEditingController(text: item.title);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _EditDialog(title: '编辑标题', controller: controller),
    );
    if (result == null) return;
    final next = result.trim();
    if (next.isEmpty || next == item.title) return;
    SoundRepository.instance.update(item.id, (s) => s.copyWith(title: next));
  }

  Future<void> _editDescription(SoundMemory item) async {
    final controller = TextEditingController(text: item.description);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _EditDialog(
        title: '编辑描述',
        controller: controller,
        maxLines: 5,
        hint: '写下这段声音的记忆…',
      ),
    );
    if (result == null) return;
    final next = result.trim();
    if (next == item.description) return;
    SoundRepository.instance.update(
      item.id,
      (s) => s.copyWith(description: next),
    );
  }

  Future<void> _editCategory(SoundMemory item) async {
    final result = await SpCategoryPicker.show(
      context,
      current: item.category,
    );
    if (result == null || result == item.category) return;
    SoundRepository.instance.updateCategory(item.id, result);
    // 声片已迁出当前分类跑道，回到 Collection 更符合语境。
    if (mounted) widget.onBack();
  }

  Future<void> _showShareSheet(SoundMemory item) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ShareSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SoundRepository.instance,
      builder: (context, _) {
        final items = _itemsForCategory();
        final index = items.isEmpty
            ? 0
            : _resolveIndex(items, preferredId: _preferredId(items));

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          body: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: AppColors.bgPrimary,
            ),
            child: SafeArea(
              child: items.isEmpty
                  ? _buildEmpty()
                  : _buildContent(items: items, index: index),
            ),
          ),
        );
      },
    );
  }

  List<SoundMemory> _itemsForCategory() {
    for (final g in SoundRepository.instance.collectionGroups) {
      if (g.category == widget.category) return g.items;
    }
    return const [];
  }

  String? _preferredId(List<SoundMemory> items) {
    if (_index >= 0 && _index < _items.length) {
      final id = _items[_index].id;
      if (items.any((s) => s.id == id)) return id;
    }
    return widget.initialSoundId;
  }

  int _resolveIndex(List<SoundMemory> items, {String? preferredId}) {
    if (items.isEmpty) return 0;
    if (preferredId != null) {
      final found = items.indexWhere((s) => s.id == preferredId);
      if (found >= 0) return found;
    }
    return _index.clamp(0, items.length - 1);
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TopBar(category: widget.category, onBack: widget.onBack),
          Expanded(
            child: EmptyStatePanel(
              statusCode: 'NO SOUNDS IN 「${widget.category}」',
              title: '这个分类还是空的',
              description: '在记录或编辑声音信息时，可以为它选择分类。',
              visual: const EmptyTrackVisual(),
              variant: EmptyStateVariant.filtered,
              primaryLabel: '查看全部收藏',
              onPrimary: widget.onBack,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent({
    required List<SoundMemory> items,
    required int index,
  }) {
    _items = items;
    _index = index;
    final item = items[index];
    final screenW = MediaQuery.sizeOf(context).width;
    // 可视化主体随整页滚动，边长约屏宽 78%（上限 360），首屏仍占主导。
    final vizSize = (screenW * 0.78).clamp(240.0, 360.0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal,
          ),
          child: _TopBar(
            category: widget.category,
            onBack: widget.onBack,
            onShare: () => _showShareSheet(item),
          ),
        ),
        Expanded(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, AppSpacing.tight, 8, 0),
                  child: Center(
                    child: SizedBox(
                      width: vizSize,
                      height: vizSize,
                      child: GestureDetector(
                        onTap: _togglePlay,
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedSwitcher(
                          duration: AppMotion.slow,
                          child: KeyedSubtree(
                            key: ValueKey('viz-${item.id}-$_playing'),
                            child: item.hasIndexedVisual
                                ? IndexedVisualPlayer(
                                    item: item,
                                    positionMsListenable: _positionMs,
                                    showProgressRing: true,
                                    progress: _progress,
                                  )
                                : SoundVisualCanvas(
                                    seed: item.visualSeed,
                                    mode: _playing
                                        ? SoundVisualMode.playback
                                        : SoundVisualMode.complete,
                                    active: _playing,
                                    dark: true,
                                    amplitude: _playing ? 0.55 : 0.2,
                                    showProgressRing: true,
                                    progress: _progress,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.item)),
              SliverToBoxAdapter(
                child: RepaintBoundary(
                  child: DiscStackCarousel(
                    key: ValueKey('stack-${widget.category}'),
                    itemCount: items.length,
                    seedAt: (i) => items[i].visualSeed,
                    titleAt: (i) => items[i].title,
                    rarityAt: (i) => items[i].resolvedRarity,
                    initialIndex: index,
                    onIndexChanged: _onIndexChanged,
                    onCenterTap: _togglePlay,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.item)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageHorizontal,
                  ),
                  child: _MemorySection(
                    item: item,
                    onEditTitle: () => _editTitle(item),
                    onEditCategory: () => _editCategory(item),
                    onEditDescription: () => _editDescription(item),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.tight)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageHorizontal,
                  ),
                  child: _InfoPanel(
                    title: '声片信息',
                    header: RarityShowcase(rarity: item.resolvedRarity),
                    collapsedRows: [
                      MetaRow(label: '声片编号', value: item.discId ?? '—'),
                    ],
                    expandedRows: [
                      MetaRow(label: '系列/批次', value: item.discSeries ?? '—'),
                      MetaRow(
                        label: '写入时间',
                        value: item.pressedAt != null
                            ? formatRecordedAt(item.pressedAt!)
                            : '—',
                      ),
                      MetaRow(
                        label: 'NFC 校验状态',
                        value: item.nfcTagId != null ? '已校验' : '未校验',
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.tight)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.pageHorizontal,
                    0,
                    AppSpacing.pageHorizontal,
                    AppSpacing.section,
                  ),
                  child: _InfoPanel(
                    title: '数字资产信息',
                    collapsedRows: [
                      MetaRow(label: '资产编号', value: item.assetId ?? '—'),
                    ],
                    expandedRows: [
                      MetaRow(
                        label: '上链时间',
                        value: item.chainedAt != null
                            ? formatRecordedAt(item.chainedAt!)
                            : '—',
                      ),
                      MetaRow(label: '网络', value: item.networkLabel),
                      MetaRow(
                        label: '链上状态',
                        value: _chainStatusLabel(item.status),
                      ),
                      MetaRow(
                        label: '交易凭证',
                        value: item.txHash ?? item.contentId ?? '—',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.category,
    required this.onBack,
    this.onShare,
  });

  final String category;
  final VoidCallback onBack;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Collection',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text(
            category,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const Spacer(),
          if (onShare != null)
            GestureDetector(
              onTap: onShare,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.ios_share_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '分享',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const SizedBox(width: 88),
        ],
      ),
    );
  }
}

/// 记忆内容：标题、分类、描述与记录信息，均可编辑（不再跳转独立页面）。
class _MemorySection extends StatelessWidget {
  const _MemorySection({
    required this.item,
    required this.onEditTitle,
    required this.onEditCategory,
    required this.onEditDescription,
  });

  final SoundMemory item;
  final VoidCallback onEditTitle;
  final VoidCallback onEditCategory;
  final VoidCallback onEditDescription;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _EditIconButton(onTap: onEditTitle),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onEditCategory,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '# ${item.category}',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.unfold_more_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.item),
          if (item.description.isEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Text(
                    '这段声音还没有留下文字记忆。',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onEditDescription,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('添加描述'),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
                _EditIconButton(onTap: onEditDescription),
              ],
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.tight),
            child: Divider(height: 1, color: AppColors.borderSubtle),
          ),
          MetaRow(label: '记录时间', value: formatRecordedAt(item.recordedAt)),
          MetaRow(
            label: '地点',
            value: item.locationLabel.isEmpty
                ? LocationCaptureService.unsetLabel
                : item.locationLabel,
          ),
          MetaRow(label: '时长', value: formatDuration(item.durationSec)),
        ],
      ),
    );
  }
}

class _EditIconButton extends StatelessWidget {
  const _EditIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(
          Icons.edit_outlined,
          size: 16,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

/// 折叠信息面板：默认展示要点，展开后补充细节；两处（声片/数字资产）复用。
class _InfoPanel extends StatefulWidget {
  const _InfoPanel({
    required this.title,
    required this.collapsedRows,
    required this.expandedRows,
    this.header,
  });

  final String title;
  final Widget? header;
  final List<Widget> collapsedRows;
  final List<Widget> expandedRows;

  @override
  State<_InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<_InfoPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.cardPadding,
                vertical: AppSpacing.tight,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (widget.header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.cardPadding,
                0,
                AppSpacing.cardPadding,
                AppSpacing.tight,
              ),
              child: widget.header!,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.cardPadding,
              0,
              AppSpacing.cardPadding,
              AppSpacing.tight,
            ),
            child: Column(children: widget.collapsedRows),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.cardPadding,
                0,
                AppSpacing.cardPadding,
                AppSpacing.tight,
              ),
              child: Column(children: widget.expandedRows),
            ),
        ],
      ),
    );
  }
}

class _EditDialog extends StatelessWidget {
  const _EditDialog({
    required this.title,
    required this.controller,
    this.maxLines = 1,
    this.hint,
  });

  final String title;
  final TextEditingController controller;
  final int maxLines;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: TextField(
        controller: controller,
        maxLines: maxLines,
        autofocus: true,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textTertiary),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.accent),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text(
            '保存',
            style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.item});

  final SoundMemory item;

  void _saveCard(BuildContext context) {
    final summary =
        '${item.title} · ${item.category} · ${item.locationLabel} · '
        '${formatRecordedAt(item.recordedAt)} · SoundPola';
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('分享卡片已准备好\n$summary'),
        backgroundColor: AppColors.surface2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageHorizontal,
          8,
          AppSpacing.pageHorizontal,
          AppSpacing.item,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sheet),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              decoration: BoxDecoration(
                color: const Color(0xE60C100F),
                borderRadius: BorderRadius.circular(AppRadii.sheet),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 0.7,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.88,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '分享收藏卡',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      Text(
                        'SoundPola',
                        style: TextStyle(
                          color: AppColors.accent.withValues(alpha: 0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '稀有度收藏卡 · 可保存分享',
                      style: TextStyle(
                        color: AppColors.textTertiary.withValues(alpha: 0.95),
                        fontSize: 12,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SoundNftCard(
                    item: item,
                    animateVisual: true,
                    compact: true,
                    variant: SoundNftCardVariant.share,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          text: '关闭',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.tight),
                      Expanded(
                        child: PrimaryButton(
                          text: '保存卡片',
                          onPressed: () => _saveCard(context),
                        ),
                      ),
                    ],
                  ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

