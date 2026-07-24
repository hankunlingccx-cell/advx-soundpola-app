import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../cloud/cloud_media_client.dart';
import '../../data/sound_repository.dart';
import '../../services/audio_playback_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/sound_visual.dart';

/// 分类胶囊（对齐 Figma 100:1023）+ 顶部色层承载分类名。
const _capsuleFill = Color(0xFF2F2F2F);
const _capsuleStroke = Color(0x3AFFFFFF); // rgba(255,255,255,0.23)
const _discFill = Color(0xFF8B8B8B);
const _discShadow = Color(0x1A000000);

/// 声片贴图资源；按 visualSeed 稳定映射，表现为随机赋予。
const _discTextures = [
  'assets/disc_textures/disc_01.png',
  'assets/disc_textures/disc_02.png',
  'assets/disc_textures/disc_03.png',
  'assets/disc_textures/disc_04.png',
  'assets/disc_textures/disc_05.png',
  'assets/disc_textures/disc_06.png',
  'assets/disc_textures/disc_07.png',
];

String _discTextureFor(int visualSeed) =>
    _discTextures[visualSeed.abs() % _discTextures.length];


/// 稿面：圆片 140、重叠 80、内边距 16；顶部色层放分类名。
const _discSize = 140.0;
const _discOverlap = 80.0;
const _capsulePad = 16.0;
const _labelBlock = 36.0;
const _columnGap = 10.0;
const _emptyCapsuleMinHeight = 120.0;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeSync();
    });
  }

  Future<void> _maybeSync() async {
    if (!AuthService.instance.isLoggedIn || _syncing) return;
    if (!mounted) return;
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

  void _openGroupSheet(CollectionGroup group) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageHorizontal,
              AppSpacing.item,
              AppSpacing.pageHorizontal,
              AppSpacing.section,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.item),
                Text(
                  group.category,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${group.count} 段收藏',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: AppSpacing.item),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: group.items.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      color: AppColors.borderSubtle,
                    ),
                    itemBuilder: (context, index) {
                      final item = group.items[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _DiscDot(textureAsset: _discTextureFor(item.visualSeed)),
                        title: Text(
                          item.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '${formatDuration(item.durationSec)} · ${item.locationLabel}',
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onOpenMemory(item.id);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
        final groups = SoundRepository.instance.collectionGroups;
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
                          : '${items.length} 段收藏 · ${groups.length} 组')
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
                              child: _CollectionWaterfall(
                                groups: groups,
                                onOpenMemory: widget.onOpenMemory,
                                onOpenGroup: _openGroupSheet,
                                onMoveToCategory: (id, category) {
                                  SoundRepository.instance
                                      .updateCategory(id, category);
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

double _discStep(double disc) => disc * (1 - _discOverlap / _discSize);

double _groupHeight({required int count, required double disc}) {
  if (count <= 0) return _emptyCapsuleMinHeight;
  // 分类名叠在顶部色层上，不额外占高。
  return _capsulePad * 2 + disc + (count - 1) * _discStep(disc);
}

/// 拖拽时补齐空分类跑道，便于改到尚无收藏的分类。
List<CollectionGroup> _groupsForLayout(
  List<CollectionGroup> groups, {
  required bool dragging,
}) {
  if (!dragging) return groups;
  final present = {for (final g in groups) g.category};
  final extras = soundCategories
      .where((c) => !present.contains(c))
      .map((c) => CollectionGroup(category: c, items: const []));
  return [...groups, ...extras];
}

/// 双列瀑布流：下一组落入当前更矮的一列。
List<List<CollectionGroup>> _splitMasonry(
  List<CollectionGroup> groups, {
  required double columnWidth,
}) {
  final disc = (columnWidth - _capsulePad * 2).clamp(0.0, _discSize);
  final columns = List.generate(2, (_) => <CollectionGroup>[]);
  final heights = List<double>.filled(2, 0);
  for (final group in groups) {
    final target = heights[0] <= heights[1] ? 0 : 1;
    columns[target].add(group);
    heights[target] +=
        _groupHeight(count: group.count, disc: disc) + AppSpacing.tight;
  }
  return columns;
}

class _CollectionWaterfall extends StatefulWidget {
  const _CollectionWaterfall({
    required this.groups,
    required this.onOpenMemory,
    required this.onOpenGroup,
    required this.onMoveToCategory,
  });

  final List<CollectionGroup> groups;
  final ValueChanged<String> onOpenMemory;
  final ValueChanged<CollectionGroup> onOpenGroup;
  final void Function(String soundId, String category) onMoveToCategory;

  @override
  State<_CollectionWaterfall> createState() => _CollectionWaterfallState();
}

class _CollectionWaterfallState extends State<_CollectionWaterfall> {
  String? _draggingId;
  String? _hoverCategory;

  void _onDragStarted(String id) {
    HapticFeedback.mediumImpact();
    setState(() {
      _draggingId = id;
      _hoverCategory = null;
    });
  }

  void _onDragEnded() {
    if (!mounted) return;
    setState(() {
      _draggingId = null;
      _hoverCategory = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dragging = _draggingId != null;
    final layoutGroups =
        _groupsForLayout(widget.groups, dragging: dragging);
    final pageW = MediaQuery.sizeOf(context).width;
    final columnWidth =
        (pageW - AppSpacing.pageHorizontal * 2 - _columnGap) / 2;
    final columns = _splitMasonry(layoutGroups, columnWidth: columnWidth);

    return Column(
      children: [
        if (dragging)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.pageHorizontal,
              0,
              AppSpacing.pageHorizontal,
              8,
            ),
            child: Text(
              '拖到目标分类跑道松开',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            physics: dragging
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageHorizontal,
              0,
              AppSpacing.pageHorizontal,
              AppSpacing.section,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < columns.length; i++) ...[
                  if (i > 0) const SizedBox(width: _columnGap),
                  Expanded(
                    child: Column(
                      children: [
                        for (final group in columns[i]) ...[
                          _CategoryCapsule(
                            group: group,
                            draggingId: _draggingId,
                            highlighted: _hoverCategory == group.category,
                            onOpenGroup: () {
                              if (_draggingId != null) return;
                              widget.onOpenGroup(group);
                            },
                            onOpenMemory: widget.onOpenMemory,
                            onDragStarted: _onDragStarted,
                            onDragEnded: _onDragEnded,
                            onHoverChanged: (active) {
                              final next = active ? group.category : null;
                              if (!active && _hoverCategory != group.category) {
                                return;
                              }
                              if (_hoverCategory == next) return;
                              setState(() => _hoverCategory = next);
                            },
                            onAccept: (soundId) {
                              widget.onMoveToCategory(
                                soundId,
                                group.category,
                              );
                              HapticFeedback.lightImpact();
                              _onDragEnded();
                            },
                          ),
                          const SizedBox(height: AppSpacing.tight),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 分组样式：#2F2F2F 跑道胶囊 + 灰圆叠片；顶部叠色层显示分类名。
class _CategoryCapsule extends StatelessWidget {
  const _CategoryCapsule({
    required this.group,
    required this.onOpenGroup,
    required this.onOpenMemory,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onHoverChanged,
    required this.onAccept,
    this.draggingId,
    this.highlighted = false,
  });

  final CollectionGroup group;
  final String? draggingId;
  final bool highlighted;
  final VoidCallback onOpenGroup;
  final ValueChanged<String> onOpenMemory;
  final ValueChanged<String> onDragStarted;
  final VoidCallback onDragEnded;
  final ValueChanged<bool> onHoverChanged;
  final ValueChanged<String> onAccept;

  @override
  Widget build(BuildContext context) {
    final count = group.items.length;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final item = SoundRepository.instance.get(details.data);
        if (item == null) return false;
        return item.category != group.category;
      },
      onMove: (_) {
        if (!highlighted) onHoverChanged(true);
      },
      onLeave: (_) => onHoverChanged(false),
      onAcceptWithDetails: (details) {
        onHoverChanged(false);
        onAccept(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        final hot = highlighted || candidateData.isNotEmpty;
        return GestureDetector(
          onTap: onOpenGroup,
          child: Semantics(
            label: '${group.category}，$count 段收藏',
            button: true,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              width: double.infinity,
              // 描边与光晕放在外层，避免 clip 裁掉导致高亮断裂
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: hot ? AppColors.accent : _capsuleStroke,
                  width: hot ? 2 : 1,
                ),
                boxShadow: hot
                    ? [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.28),
                          blurRadius: 14,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(98),
                child: ColoredBox(
                  color: _capsuleFill,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final disc = (constraints.maxWidth - _capsulePad * 2)
                          .clamp(0.0, _discSize);
                      final yStep = _discStep(disc);
                      final stackH = count == 0
                          ? 0.0
                          : disc + (count - 1) * yStep;
                      final bodyH = count == 0
                          ? _emptyCapsuleMinHeight
                          : _capsulePad * 2 + stackH;

                      return SizedBox(
                        height: bodyH,
                        child: Stack(
                          children: [
                            if (count > 0)
                              Positioned(
                                top: _capsulePad,
                                left: _capsulePad,
                                right: _capsulePad,
                                height: stackH,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    for (var i = 0; i < count; i++)
                                      Positioned(
                                        top: i * yStep,
                                        left: ((constraints.maxWidth -
                                                    _capsulePad * 2) -
                                                disc) /
                                            2,
                                        child: _SoundDisc(
                                          size: disc,
                                          soundId: group.items[i].id,
                                          textureAsset: _discTextureFor(
                                            group.items[i].visualSeed,
                                          ),
                                          lifting:
                                              draggingId == group.items[i].id,
                                          onTap: () =>
                                              onOpenMemory(group.items[i].id),
                                          onDragStarted: onDragStarted,
                                          onDragEnded: onDragEnded,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: _labelBlock + 36,
                              child: const IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xF52F2F2F),
                                        Color(0xD92F2F2F),
                                        Color(0x992F2F2F),
                                        Color(0x4D2F2F2F),
                                        Color(0x142F2F2F),
                                        Color(0x002F2F2F),
                                      ],
                                      stops: [
                                        0.0,
                                        0.22,
                                        0.45,
                                        0.68,
                                        0.88,
                                        1.0,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 14,
                              left: 10,
                              right: 10,
                              child: IgnorePointer(
                                child: Text(
                                  group.category,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: hot
                                        ? AppColors.accent
                                        : AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ),
                            // 最上层再描一圈完整高亮环，避免被圆片/罩层遮断
                            if (hot)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(98),
                                      border: Border.all(
                                        color: AppColors.accent
                                            .withValues(alpha: 0.95),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SoundDisc extends StatelessWidget {
  const _SoundDisc({
    required this.size,
    required this.soundId,
    required this.textureAsset,
    required this.onTap,
    required this.onDragStarted,
    required this.onDragEnded,
    this.lifting = false,
  });

  final double size;
  final String soundId;
  final String textureAsset;
  final bool lifting;
  final VoidCallback onTap;
  final ValueChanged<String> onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<String>(
      data: soundId,
      hapticFeedbackOnStart: true,
      delay: const Duration(milliseconds: 260),
      onDragStarted: () => onDragStarted(soundId),
      onDragEnd: (_) => onDragEnded(),
      onDraggableCanceled: (_, _) => onDragEnded(),
      feedback: Material(
        color: Colors.transparent,
        elevation: 0,
        child: Transform.scale(
          scale: 1.14,
          child: _DiscVisual(
            size: size,
            textureAsset: textureAsset,
            floating: true,
          ),
        ),
      ),
      // 原位留下淡影，表达「从跑道中浮出」
      childWhenDragging: Opacity(
        opacity: 0.18,
        child: _DiscVisual(size: size, textureAsset: textureAsset),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: lifting ? null : onTap,
        child: AnimatedScale(
          scale: lifting ? 0.96 : 1,
          duration: AppMotion.fast,
          child: _DiscVisual(size: size, textureAsset: textureAsset),
        ),
      ),
    );
  }
}

class _DiscVisual extends StatelessWidget {
  const _DiscVisual({
    required this.size,
    required this.textureAsset,
    this.floating = false,
  });

  final double size;
  final String textureAsset;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _discFill,
        border: floating
            ? Border.all(
                color: AppColors.accent.withValues(alpha: 0.55),
                width: 1.5,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: floating
                ? Colors.black.withValues(alpha: 0.45)
                : _discShadow,
            offset: floating ? const Offset(0, 10) : const Offset(-3, 0),
            blurRadius: floating ? 22 : 4,
          ),
          if (!floating)
            const BoxShadow(
              color: _discShadow,
              offset: Offset(0, -5),
              blurRadius: 10,
            ),
          if (floating)
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.28),
              blurRadius: 18,
            ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          textureAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => ColoredBox(color: _discFill),
        ),
      ),
    );
  }
}

class _DiscDot extends StatelessWidget {
  const _DiscDot({required this.textureAsset});

  final String textureAsset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: _discFill,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _discShadow,
            offset: Offset(-2, 0),
            blurRadius: 3,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          textureAsset,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(color: _discFill),
        ),
      ),
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
