import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../cloud/cloud_media_client.dart';
import '../../data/disc_rarity.dart';
import '../../data/sound_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/disc_texture.dart';
import '../../widgets/empty_state_panel.dart';
import '../../widgets/ssr_aura_layer.dart';

/// 玻璃跑道胶囊色值（半透明，配合 BackdropFilter）。
const _capsuleGlassTop = Color(0xCC3A3A3A);
const _capsuleGlassBottom = Color(0xB31C1C1C);
const _capsuleStroke = Color(0x59FFFFFF);
const _capsuleStrokeInner = Color(0x1AFFFFFF);

/// 稿面：圆片 140、重叠 80、内边距 16；顶部色层放分类名。
const _discSize = 140.0;
const _discOverlap = 80.0;
const _capsulePad = 16.0;
const _labelBlock = 36.0;
const _columnGap = 10.0;
const _emptyCapsuleMinHeight = 120.0;

typedef OpenCategoryPlay = void Function(String category, {String? soundId});

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({
    super.key,
    required this.onOpenCategoryPlay,
    required this.onStartRecord,
    required this.onOpenDrafts,
    required this.onLogin,
  });

  final OpenCategoryPlay onOpenCategoryPlay;
  final VoidCallback onStartRecord;
  final VoidCallback onOpenDrafts;
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
                          ? _CollectionEmpty(
                              syncing: _syncing,
                              draftCount: SoundRepository.instance.draftCount,
                              onStartRecord: widget.onStartRecord,
                              onOpenDrafts: widget.onOpenDrafts,
                            )
                          : RefreshIndicator(
                              onRefresh: _maybeSync,
                              color: AppColors.accent,
                              child: _CollectionWaterfall(
                                groups: groups,
                                onOpenCategoryPlay: widget.onOpenCategoryPlay,
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
  final extras = SoundRepository.instance.categories
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
    required this.onOpenCategoryPlay,
    required this.onMoveToCategory,
  });

  final List<CollectionGroup> groups;
  final OpenCategoryPlay onOpenCategoryPlay;
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageHorizontal,
              0,
              AppSpacing.pageHorizontal,
              8,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        AppColors.accent.withValues(alpha: 0.18),
                        AppColors.accent.withValues(alpha: 0.08),
                      ],
                    ),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Text(
                    '拖到目标分类跑道松开',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.accentSoft,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
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
                              // 点击分类跑道 → 进入该分类声片播放页
                              widget.onOpenCategoryPlay(group.category);
                            },
                            onOpenDisc: (soundId) {
                              if (_draggingId != null) return;
                              widget.onOpenCategoryPlay(
                                group.category,
                                soundId: soundId,
                              );
                            },
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

/// 分组样式：玻璃拟物跑道 + 声片叠放；顶部玻璃罩显示分类名。
class _CategoryCapsule extends StatelessWidget {
  const _CategoryCapsule({
    required this.group,
    required this.onOpenGroup,
    required this.onOpenDisc,
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
  final ValueChanged<String> onOpenDisc;
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
        if (!highlighted) {
          HapticFeedback.selectionClick();
          onHoverChanged(true);
        }
      },
      onLeave: (_) => onHoverChanged(false),
      onAcceptWithDetails: (details) {
        onHoverChanged(false);
        onAccept(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        final hot = highlighted || candidateData.isNotEmpty;
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onOpenGroup();
          },
          child: Semantics(
            label: '${group.category}，$count 段收藏',
            button: true,
            child: AnimatedScale(
              scale: hot ? 1.02 : 1.0,
              duration: AppMotion.fast,
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: AppMotion.normal,
                curve: Curves.easeOutCubic,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: hot
                        ? AppColors.accent.withValues(alpha: 0.9)
                        : _capsuleStroke,
                    width: hot ? 1.6 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: hot ? 0.55 : 0.38),
                      offset: Offset(0, hot ? 14 : 10),
                      blurRadius: hot ? 28 : 18,
                    ),
                    if (hot)
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.32),
                        blurRadius: 22,
                        spreadRadius: 0.5,
                      )
                    else
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.04),
                        offset: const Offset(0, -1),
                        blurRadius: 0,
                      ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(98),
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      // 毛玻璃底
                      Positioned.fill(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: hot ? 22 : 16,
                            sigmaY: hot ? 22 : 16,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      // 玻璃渐变填充
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: hot
                                  ? [
                                      AppColors.accent.withValues(alpha: 0.22),
                                      _capsuleGlassTop,
                                      _capsuleGlassBottom,
                                    ]
                                  : [
                                      _capsuleGlassTop,
                                      const Color(0xB3282828),
                                      _capsuleGlassBottom,
                                    ],
                              stops: hot
                                  ? const [0.0, 0.35, 1.0]
                                  : const [0.0, 0.45, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // 顶部高光条（拟物玻璃反光）
                      Positioned(
                        top: 0,
                        left: 12,
                        right: 12,
                        height: 42,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(80),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(alpha: 0.22),
                                  Colors.white.withValues(alpha: 0.06),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 内描边
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(98),
                              border: Border.all(
                                color: hot
                                    ? AppColors.accent.withValues(alpha: 0.35)
                                    : _capsuleStrokeInner,
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      LayoutBuilder(
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
                                              textureAsset: discTextureFor(
                                                group.items[i].visualSeed,
                                              ),
                                              rarity: group.items[i].discRarity,
                                              lifting: draggingId ==
                                                  group.items[i].id,
                                              onTap: () => onOpenDisc(
                                                group.items[i].id,
                                              ),
                                              onDragStarted: onDragStarted,
                                              onDragEnded: onDragEnded,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                // 分类名玻璃罩
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  height: _labelBlock + 40,
                                  child: IgnorePointer(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.black.withValues(alpha: 0.55),
                                            Colors.black.withValues(alpha: 0.28),
                                            Colors.black.withValues(alpha: 0.0),
                                          ],
                                          stops: const [0.0, 0.45, 1.0],
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
                                            ? AppColors.accentHighlight
                                            : AppColors.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        height: 1.2,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.55),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                if (hot)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(98),
                                          border: Border.all(
                                            color: AppColors.accent
                                                .withValues(alpha: 0.85),
                                            width: 1.4,
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
                    ],
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

class _SoundDisc extends StatefulWidget {
  const _SoundDisc({
    required this.size,
    required this.soundId,
    required this.textureAsset,
    required this.onTap,
    required this.onDragStarted,
    required this.onDragEnded,
    this.rarity,
    this.lifting = false,
  });

  final double size;
  final String soundId;
  final String textureAsset;
  final DiscRarity? rarity;
  final bool lifting;
  final VoidCallback onTap;
  final ValueChanged<String> onDragStarted;
  final VoidCallback onDragEnded;

  @override
  State<_SoundDisc> createState() => _SoundDiscState();
}

class _SoundDiscState extends State<_SoundDisc> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = widget.lifting
        ? 0.94
        : _pressed
            ? 0.93
            : 1.0;

    return LongPressDraggable<String>(
      data: widget.soundId,
      hapticFeedbackOnStart: true,
      delay: const Duration(milliseconds: 240),
      onDragStarted: () {
        setState(() => _pressed = false);
        widget.onDragStarted(widget.soundId);
      },
      onDragEnd: (_) => widget.onDragEnded(),
      onDraggableCanceled: (_, _) => widget.onDragEnded(),
      feedback: Material(
        color: Colors.transparent,
        elevation: 0,
        child: Transform.scale(
          scale: 1.18,
          child: _DiscVisual(
            size: widget.size,
            textureAsset: widget.textureAsset,
            rarity: widget.rarity,
            floating: true,
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.16,
        child: _DiscVisual(
          size: widget.size,
          textureAsset: widget.textureAsset,
          rarity: widget.rarity,
          dimmed: true,
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.lifting
            ? null
            : (_) {
                setState(() => _pressed = true);
                HapticFeedback.selectionClick();
              },
        onTapUp: widget.lifting
            ? null
            : (_) {
                setState(() => _pressed = false);
                widget.onTap();
              },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: AppMotion.fast,
          curve: Curves.easeOutCubic,
          child: _DiscVisual(
            size: widget.size,
            textureAsset: widget.textureAsset,
            rarity: widget.rarity,
            pressed: _pressed,
          ),
        ),
      ),
    );
  }
}

/// 稀有度暂以贴图区分（后续按等级换贴图）；卡面统一叠加镭射扫光。
class _DiscVisual extends StatefulWidget {
  const _DiscVisual({
    required this.size,
    required this.textureAsset,
    this.rarity,
    this.floating = false,
    this.pressed = false,
    this.dimmed = false,
  });

  final double size;
  final String textureAsset;
  final DiscRarity? rarity;
  final bool floating;
  final bool pressed;
  final bool dimmed;

  @override
  State<_DiscVisual> createState() => _DiscVisualState();
}

class _DiscVisualState extends State<_DiscVisual>
    with SingleTickerProviderStateMixin {
  AnimationController? _laser;

  bool get _needsLaser => !widget.dimmed;

  @override
  void initState() {
    super.initState();
    _syncLaser();
  }

  @override
  void didUpdateWidget(covariant _DiscVisual oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dimmed != widget.dimmed) {
      _syncLaser();
    }
  }

  void _syncLaser() {
    if (_needsLaser) {
      _laser ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 3600),
      )..repeat();
    } else {
      _laser?.stop();
    }
  }

  @override
  void dispose() {
    _laser?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final floating = widget.floating;
    final pressed = widget.pressed;
    final dimmed = widget.dimmed;
    final rim = size * 0.035;

    final glow = AppColors.accent.withValues(
      alpha: floating ? 0.36 : 0.18,
    );

    final face = Stack(
      alignment: Alignment.center,
      children: [
        ClipOval(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Colors.white,
                ),
                Opacity(
                  opacity: dimmed ? 0.18 : 0.48,
                  child: Image.asset(
                    widget.textureAsset,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                ColoredBox(
                  color: Colors.white.withValues(
                    alpha: dimmed ? 0.3 : 0.08,
                  ),
                ),
                if (_needsLaser && _laser != null)
                  AnimatedBuilder(
                    animation: _laser!,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _HoloSheenPainter(
                          t: _laser!.value,
                          intensity: 0.9,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        IgnorePointer(
          child: ClipOval(
            child: SizedBox(
              width: size,
              height: size,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: const Alignment(-0.8, -1),
                    end: const Alignment(0.4, 0.35),
                    colors: [
                      Colors.white.withValues(
                        alpha: floating ? 0.42 : 0.32,
                      ),
                      Colors.white.withValues(alpha: 0.08),
                      Colors.transparent,
                      Colors.black.withValues(alpha: pressed ? 0.18 : 0.1),
                    ],
                    stops: const [0.0, 0.28, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: floating
                    ? AppColors.accent.withValues(alpha: 0.75)
                    : AppColors.accent.withValues(alpha: 0.55),
                width: floating ? 1.6 : 1.3,
              ),
            ),
          ),
        ),
        if (!dimmed)
          IgnorePointer(
            child: Container(
              width: size - 3,
              height: size - 3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFD879C8).withValues(alpha: 0.28),
                  width: 0.8,
                ),
              ),
            ),
          ),
        IgnorePointer(
          child: Container(
            width: size - rim * 2,
            height: size - rim * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.18),
                width: 0.8,
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Container(
            width: size * 0.12,
            height: size * 0.12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.35),
                  Colors.white.withValues(alpha: 0.05),
                  Colors.transparent,
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 0.6,
              ),
            ),
          ),
        ),
      ],
    );

    return AnimatedContainer(
      duration: AppMotion.fast,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: floating ? 0.55 : 0.35),
            offset: Offset(0, floating ? 16 : (pressed ? 2 : 6)),
            blurRadius: floating ? 28 : (pressed ? 6 : 12),
            spreadRadius: floating ? 1 : 0,
          ),
          if (!floating)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              offset: const Offset(0, -4),
              blurRadius: 10,
            ),
          if (floating || !dimmed)
            BoxShadow(
              color: glow,
              blurRadius: 26,
              spreadRadius: 1,
            ),
          BoxShadow(
            color: Colors.white.withValues(alpha: floating ? 0.12 : 0.06),
            offset: const Offset(-2, -3),
            blurRadius: 6,
          ),
        ],
      ),
      child: SsrAuraLayer(
        size: size,
        enabled: SsrAuraLayer.isSsr(widget.rarity) && !dimmed,
        intensity: floating ? 1.0 : 0.55,
        parallax: floating
            ? const Offset(2.5, -1.5)
            : (pressed ? const Offset(1.2, 0.8) : Offset.zero),
        child: face,
      ),
    );
  }
}

/// 全等级镭射折射扫光（稀有度差异后续由贴图承担）。
class _HoloSheenPainter extends CustomPainter {
  _HoloSheenPainter({required this.t, required this.intensity});

  final double t;
  final double intensity;

  static const _colors = [
    Color(0x0063E0CB),
    Color(0xA663E0CB),
    Color(0x994FA9E8),
    Color(0x997667E8),
    Color(0x99D879C8),
    Color(0xA663E0CB),
    Color(0x0063E0CB),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final angle = t * math.pi * 2;
    final paint = Paint()
      ..blendMode = BlendMode.softLight
      ..shader = SweepGradient(
        startAngle: angle,
        endAngle: angle + math.pi * 2,
        colors: _colors
            .map(
              (c) => c.withValues(alpha: (c.a * intensity).clamp(0.0, 1.0)),
            )
            .toList(),
        stops: const [0.0, 0.14, 0.32, 0.48, 0.64, 0.82, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    // 斜向高亮带
    final band = Paint()
      ..blendMode = BlendMode.plus
      ..shader = LinearGradient(
        begin: Alignment(-1 + 2 * t, -1),
        end: Alignment(t, 1),
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.18 * intensity),
          const Color(0xFF63E0CB).withValues(alpha: 0.22 * intensity),
          Colors.transparent,
        ],
        stops: const [0.35, 0.48, 0.55, 0.7],
      ).createShader(rect);
    canvas.drawRect(rect, band);
  }

  @override
  bool shouldRepaint(covariant _HoloSheenPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.intensity != intensity;
}

class _CollectionEmpty extends StatelessWidget {
  const _CollectionEmpty({
    required this.syncing,
    required this.draftCount,
    required this.onStartRecord,
    required this.onOpenDrafts,
  });

  final bool syncing;
  final int draftCount;
  final VoidCallback onStartRecord;
  final VoidCallback onOpenDrafts;

  @override
  Widget build(BuildContext context) {
    if (syncing) {
      return const EmptyStatePanel(
        statusCode: 'SYNCING COLLECTION',
        title: '正在同步数字收藏',
        description: '确认同步完成前，不会把列表当成空收藏。',
        visual: EmptyTrackVisual(),
        variant: EmptyStateVariant.processing,
      );
    }

    if (draftCount > 0) {
      final count = draftCount.toString().padLeft(2, '0');
      return EmptyStatePanel(
        statusCode: 'NO ASSETS YET',
        title: '你有 $count 段声音等待封存',
        description: '完成实体声片写入后，它们才会进入 Collection。',
        visual: EmptyTrackVisual(pendingSlots: draftCount.clamp(1, 5)),
        variant: EmptyStateVariant.processing,
        primaryLabel: '前往封存',
        onPrimary: onOpenDrafts,
      );
    }

    return EmptyStatePanel(
      statusCode: 'COLLECTION EMPTY',
      title: '你的数字收藏尚未开始',
      description: '只有写入实体声片并完成上链后，声音才会成为数字收藏资产。',
      visual: const EmptyTrackVisual(),
      primaryLabel: '录下第一段声音',
      onPrimary: onStartRecord,
      secondaryLabel: '查看暂存声音',
      onSecondary: onOpenDrafts,
    );
  }
}

class _LoginGate extends StatelessWidget {
  const _LoginGate({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return EmptyStatePanel(
      statusCode: 'ACCOUNT OFFLINE',
      title: '登录以查看你的资产',
      description: '登录后可同步 Collection，查看 NFT 状态与收藏记录。',
      visual: const EmptyTrackVisual(),
      variant: EmptyStateVariant.blocked,
      primaryLabel: '登录 / 创建账户',
      onPrimary: onLogin,
    );
  }
}
