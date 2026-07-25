import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/sound_repository.dart';
import '../../services/audio_playback_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/sound_visual.dart';

/// Horizontal overlapping draft deck (not a flat PageView list).
///
/// Center card full · neighbors peek 18–24% · slight rotation / drop / scale.
class DraftTrayCarousel extends StatefulWidget {
  const DraftTrayCarousel({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onIndexChanged,
    required this.onOpenDetail,
    required this.onLongPressCenter,
    this.onLongPressMove,
    this.onLongPressEnd,
    this.dimmed = false,
    this.locked = false,
    this.placeholderIndex,
    this.centerCardKey,
    this.spreadPeers = false,
  });

  final List<SoundMemory> items;
  final int selectedIndex;
  final ValueChanged<int> onIndexChanged;
  final ValueChanged<String> onOpenDetail;
  final void Function(LongPressStartDetails details, int index) onLongPressCenter;
  final void Function(LongPressMoveUpdateDetails details)? onLongPressMove;
  final void Function(LongPressEndDetails details)? onLongPressEnd;
  final bool dimmed;
  final bool locked;
  final int? placeholderIndex;
  final GlobalKey? centerCardKey;
  /// When true (dragging center), peer cards ease outward.
  final bool spreadPeers;

  @override
  State<DraftTrayCarousel> createState() => _DraftTrayCarouselState();
}

class _DraftTrayCarouselState extends State<DraftTrayCarousel>
    with SingleTickerProviderStateMixin {
  static const _cardW = 178.0;
  static const _cardH = 232.0;
  /// Center-to-center step as fraction of card width → ~72% overlap.
  static const _overlapStep = 0.28;

  late final AnimationController _settle;
  double _dragDx = 0;
  bool _swipeArmed = false;

  int get _index => widget.selectedIndex
      .clamp(0, math.max(0, widget.items.length - 1))
      .toInt();

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _goTo(int next) {
    if (widget.locked || widget.items.isEmpty) return;
    final clamped = next.clamp(0, widget.items.length - 1);
    if (clamped == _index) return;
    HapticFeedback.selectionClick();
    widget.onIndexChanged(clamped);
    _settle
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final n = widget.items.length;
    final selected = _index;
    // Show up to 2 on each side (3–5 total).
    final lo = math.max(0, selected - 2);
    final hi = math.min(n - 1, selected + 2);

    return AnimatedOpacity(
      duration: AppMotion.fast,
      opacity: widget.dimmed ? 0.55 : 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final step = _cardW * _overlapStep;
          final spread = widget.spreadPeers ? 18.0 : 0.0;

          // Paint back → front so center is on top.
          final order = <int>[
            for (var i = lo; i <= hi; i++) i,
          ]..sort((a, b) {
              final da = (a - selected).abs();
              final db = (b - selected).abs();
              return db.compareTo(da);
            });

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: widget.locked
                ? null
                : (_) {
                    _swipeArmed = true;
                    _dragDx = 0;
                  },
            onHorizontalDragUpdate: widget.locked
                ? null
                : (d) {
                    if (!_swipeArmed) return;
                    setState(() => _dragDx += d.delta.dx);
                  },
            onHorizontalDragEnd: widget.locked
                ? null
                : (d) {
                    if (!_swipeArmed) return;
                    _swipeArmed = false;
                    final v = d.primaryVelocity ?? 0;
                    final threshold = step * 0.35;
                    if (_dragDx < -threshold || v < -420) {
                      _goTo(selected + 1);
                    } else if (_dragDx > threshold || v > 420) {
                      _goTo(selected - 1);
                    }
                    setState(() => _dragDx = 0);
                  },
            child: AnimatedBuilder(
              animation: _settle,
              builder: (context, _) {
                return Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    for (final i in order)
                      _buildCardSlot(
                        index: i,
                        selected: selected,
                        step: step,
                        spread: spread,
                        maxH: constraints.maxHeight,
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardSlot({
    required int index,
    required int selected,
    required double step,
    required double spread,
    required double maxH,
  }) {
    final delta = (index - selected).toDouble();
    final abs = delta.abs();
    final isCenter = index == selected;
    final isPlaceholder = widget.placeholderIndex == index;

    // Layer params
    double scale;
    double rotDeg;
    double yOff;
    double opacity;
    if (abs < 0.01) {
      scale = 1.0;
      rotDeg = 0;
      yOff = 0;
      opacity = 1;
    } else if (abs < 1.5) {
      scale = ui.lerpDouble(1.0, 0.95, abs.clamp(0.0, 1.0))!;
      rotDeg = delta.sign * ui.lerpDouble(0, 2.0, abs.clamp(0.0, 1.0))!;
      yOff = ui.lerpDouble(0, 6.5, abs.clamp(0.0, 1.0))!;
      opacity = ui.lerpDouble(1.0, 0.9, abs.clamp(0.0, 1.0))!;
    } else {
      scale = ui.lerpDouble(0.95, 0.90, ((abs - 1) / 1).clamp(0.0, 1.0))!;
      rotDeg = delta.sign * ui.lerpDouble(2.0, 2.8, ((abs - 1) / 1).clamp(0.0, 1.0))!;
      yOff = ui.lerpDouble(6.5, 12.0, ((abs - 1) / 1).clamp(0.0, 1.0))!;
      opacity = ui.lerpDouble(0.9, 0.84, ((abs - 1) / 1).clamp(0.0, 1.0))!;
    }

    // Stable per-card micro rotation (seeded, not chaotic).
    final micro = ((index * 17) % 7 - 3) * 0.15;
    if (!isCenter) rotDeg += micro;

    var x = delta * step + (_swipeArmed ? _dragDx * (isCenter ? 1.0 : 0.35) : 0);
    if (!isCenter) x += delta.sign * spread;

    final cardH = math.min(_cardH, maxH.isFinite ? maxH * 0.92 : _cardH);

    return Transform.translate(
      offset: Offset(x, yOff),
      child: Transform.rotate(
        angle: rotDeg * math.pi / 180,
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: SizedBox(
              width: _cardW,
              height: cardH,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Ghost slot while dragging — keeps layout hierarchy.
                  if (isPlaceholder) const _DraftCardPlaceholder(),
                  // Keep the real card mounted (invisible) so long-press
                  // move/end recognizers are not disposed mid-drag.
                  Opacity(
                    opacity: isPlaceholder ? 0 : 1,
                    child: DraftTrayCard(
                      key: isCenter
                          ? widget.centerCardKey
                          : ValueKey(widget.items[index].id),
                      item: widget.items[index],
                      draftNumber: index + 1,
                      tintIndex: index,
                      elevated: isCenter && !widget.dimmed,
                      onTap: () {
                        if (widget.locked) return;
                        if (isCenter) {
                          widget.onOpenDetail(widget.items[index].id);
                        } else {
                          _goTo(index);
                        }
                      },
                      onLongPressStart: isCenter && !widget.locked
                          ? (d) => widget.onLongPressCenter(d, index)
                          : null,
                      onLongPressMoveUpdate:
                          isCenter ? widget.onLongPressMove : null,
                      onLongPressEnd:
                          isCenter ? widget.onLongPressEnd : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DraftCardPlaceholder extends StatelessWidget {
  const _DraftCardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AppColors.ceramic.withValues(alpha: 0.14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
    );
  }
}

Color _cardBase(int index) {
  const tints = [
    AppColors.cardIvory,
    AppColors.cardCool,
    AppColors.cardSilver,
  ];
  return tints[index % tints.length];
}

Color categoryAccent(String category) {
  final c = category.trim();
  if (c.contains('自然')) return const Color(0xFF8BE58A);
  if (c.contains('城市') || c.contains('旅行')) return const Color(0xFF687CFF);
  if (c.contains('人声')) return const Color(0xFFFF729F);
  if (c.contains('特别') || c.contains('日常')) return const Color(0xFFFFD65A);
  return AppColors.accent;
}

/// Physical sound medium card — paper-plastic composite, one accent only.
class DraftTrayCard extends StatelessWidget {
  const DraftTrayCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.elevated = false,
    this.scale = 1,
    this.tintIndex = 0,
    this.draftNumber = 1,
    this.playingOverride,
    this.progressOverride,
  });

  final SoundMemory item;
  final VoidCallback onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;
  final bool elevated;
  final double scale;
  final int tintIndex;
  final int draftNumber;
  final bool? playingOverride;
  final double? progressOverride;

  String get _statusLine {
    return switch (item.status) {
      SoundStatus.drafted => 'READY TO PRESS',
      SoundStatus.writeFailed || SoundStatus.chainFailed => 'READY TO PRESS',
      SoundStatus.writing ||
      SoundStatus.cloudReady ||
      SoundStatus.chainPending ||
      SoundStatus.chainReady =>
        'PRESSING',
      SoundStatus.collected => 'SEALED',
    };
  }

  String get _dateLabel {
    final d = item.recordedAt;
    final mo = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}.$mo.$day';
  }

  @override
  Widget build(BuildContext context) {
    final base = _cardBase(tintIndex);
    final accent = categoryAccent(item.category);
    final numLabel = draftNumber.toString().padLeft(2, '0');

    return Transform.scale(
      scale: scale,
      child: GestureDetector(
        onTap: onTap,
        onLongPressStart: onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        onLongPressEnd: onLongPressEnd,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: const Alignment(-0.55, -1),
              end: const Alignment(0.45, 1),
              colors: [
                Colors.white,
                base,
                Color.lerp(base, const Color(0xFFD8DDDA), 0.4)!,
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: elevated ? 0.95 : 0.5),
              width: 0.9,
            ),
            boxShadow: [
              // Thickness / contact shadow
              BoxShadow(
                color: Colors.black.withValues(alpha: elevated ? 0.42 : 0.26),
                blurRadius: elevated ? 28 : 16,
                offset: Offset(0, elevated ? 14 : 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 2,
                offset: const Offset(1.5, 2.5),
              ),
              // Top edge highlight
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.55),
                blurRadius: 0.6,
                offset: const Offset(0, -0.7),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                // Left category accent strip (single accent)
                Positioned(
                  left: 0,
                  top: 18,
                  bottom: 18,
                  child: Container(
                    width: 3.2,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.85),
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'DRAFT / $numLabel',
                            style: TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 11,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink.withValues(alpha: 0.45),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withValues(alpha: 0.9),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: _CircularPlayVisual(
                          item: item,
                          size: 96,
                          playingOverride: playingOverride,
                          progressOverride: progressOverride,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                          height: 1.15,
                          letterSpacing: -0.25,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${item.category} · ${formatDuration(item.durationSec)} · $_dateLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Courier',
                          color: AppColors.inkMuted.withValues(alpha: 0.95),
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _statusLine,
                        style: TextStyle(
                          color: elevated ? AppColors.accent : AppColors.inkMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CircularPlayVisual extends StatelessWidget {
  const _CircularPlayVisual({
    required this.item,
    this.size = 96,
    this.playingOverride,
    this.progressOverride,
  });

  final SoundMemory item;
  final double size;
  final bool? playingOverride;
  final double? progressOverride;

  @override
  Widget build(BuildContext context) {
    final player = AudioPlaybackService.instance;
    final inner = size - 12;

    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final path = item.audioPath;
        final isThis =
            path != null && path.isNotEmpty && player.currentPath == path;
        final playing = playingOverride ?? (isThis && player.isPlaying);
        final progress = progressOverride ??
            (isThis ? player.progress : (playing ? 0.35 : 0));

        return GestureDetector(
          onTap: () async {
            if (path == null || path.isEmpty) return;
            await player.play(path);
          },
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size(size, size),
                  painter: _RingPainter(
                    progress: playing || progress > 0 ? progress : 0,
                    active: playing,
                  ),
                ),
                ClipOval(
                  child: SizedBox(
                    width: inner,
                    height: inner,
                    child: ColoredBox(
                      color: AppColors.glassDark,
                      child: SoundVisualCanvas(
                        seed: item.visualSeed,
                        mode: playing
                            ? SoundVisualMode.playback
                            : SoundVisualMode.complete,
                      ),
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

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.active});

  final double progress;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = AppColors.silver.withValues(alpha: 0.75),
    );
    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..color = AppColors.accent.withValues(alpha: active ? 0.95 : 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.active != active;
}
