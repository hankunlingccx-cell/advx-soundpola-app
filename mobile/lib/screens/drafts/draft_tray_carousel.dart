import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/sound_repository.dart';
import '../../services/audio_playback_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/sound_visual.dart';

/// 横向错位堆叠的声音暂存卡片托盘。
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
  /// 拖起时保留占位轮廓的索引。
  final int? placeholderIndex;
  final GlobalKey? centerCardKey;

  @override
  State<DraftTrayCarousel> createState() => _DraftTrayCarouselState();
}

class _DraftTrayCarouselState extends State<DraftTrayCarousel> {
  static const _viewportFraction = 0.58;
  late final PageController _controller;
  double _page = 0;

  @override
  void initState() {
    super.initState();
    final i =
        widget.selectedIndex.clamp(0, math.max(0, widget.items.length - 1)).toInt();
    _page = i.toDouble();
    _controller = PageController(
      initialPage: i,
      viewportFraction: _viewportFraction,
    );
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant DraftTrayCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.isEmpty) return;
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.items.length != widget.items.length) {
      final next = widget.selectedIndex.clamp(0, widget.items.length - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        if ((_controller.page ?? _page).round() != next) {
          _controller.animateToPage(
            next,
            duration: AppMotion.normal,
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients || !_controller.position.haveDimensions) return;
    final page = _controller.page ?? _page;
    if ((page - _page).abs() < 0.001) return;
    setState(() => _page = page);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      duration: AppMotion.normal,
      opacity: widget.dimmed ? 0.45 : 1,
      child: PageView.builder(
        controller: _controller,
        itemCount: widget.items.length,
        physics: widget.locked || widget.placeholderIndex != null
            ? const NeverScrollableScrollPhysics()
            : const BouncingScrollPhysics(),
        onPageChanged: (i) {
          HapticFeedback.selectionClick();
          widget.onIndexChanged(i);
        },
        itemBuilder: (context, index) {
            final item = widget.items[index];
            final delta = index - _page;
            final abs = delta.abs().clamp(0.0, 1.5);
            final scale = uiLerp(1.0, 0.86, (abs / 1.2).clamp(0.0, 1.0));
            final brightness = uiLerp(1.0, 0.55, (abs / 1.0).clamp(0.0, 1.0));
            final yOffset = abs * 10;
            final isCenter = index == widget.selectedIndex;
            final isPlaceholder = widget.placeholderIndex == index;

            return Transform.translate(
              offset: Offset(delta * 6, yOffset),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: brightness,
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (isPlaceholder) const _DraftCardPlaceholder(),
                        Opacity(
                          opacity: isPlaceholder ? 0 : 1,
                          child: DraftTrayCard(
                            key: isCenter ? widget.centerCardKey : null,
                            item: item,
                            elevated: isCenter && !widget.dimmed,
                            onTap: () => widget.onOpenDetail(item.id),
                            onLongPressStart: isCenter && !widget.locked
                                ? (d) => widget.onLongPressCenter(d, index)
                                : null,
                            onLongPressMoveUpdate: isCenter
                                ? widget.onLongPressMove
                                : null,
                            onLongPressEnd:
                                isCenter ? widget.onLongPressEnd : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
  }
}

double uiLerp(double a, double b, double t) => a + (b - a) * t;

class _DraftCardPlaceholder extends StatelessWidget {
  const _DraftCardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.22),
          width: 1.2,
        ),
        color: AppColors.surface1.withValues(alpha: 0.25),
      ),
    );
  }
}

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
  final bool? playingOverride;
  final double? progressOverride;

  String get _statusLine {
    return switch (item.status) {
      SoundStatus.drafted => 'UNPRESSED',
      SoundStatus.writeFailed => 'READY TO PRESS',
      SoundStatus.chainFailed => 'READY TO PRESS',
      SoundStatus.writing || SoundStatus.chainPending => 'PRESSING',
      SoundStatus.collected => 'PRESSED',
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
    return Transform.scale(
      scale: scale,
      child: GestureDetector(
        onTap: onTap,
        onLongPressStart: onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        onLongPressEnd: onLongPressEnd,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          width: 168,
          height: 220,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: elevated ? AppColors.surface2 : AppColors.surface1,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: elevated
                  ? AppColors.accent.withValues(alpha: 0.28)
                  : AppColors.borderSubtle,
            ),
            boxShadow: elevated
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: _CircularPlayVisual(
                  item: item,
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
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${item.category} · ${formatDuration(item.durationSec)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
              Text(
                _dateLabel,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                _statusLine,
                style: TextStyle(
                  color: AppColors.accent.withValues(alpha: 0.85),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'RARITY ?',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircularPlayVisual extends StatelessWidget {
  const _CircularPlayVisual({
    required this.item,
    this.playingOverride,
    this.progressOverride,
  });

  final SoundMemory item;
  final bool? playingOverride;
  final double? progressOverride;

  @override
  Widget build(BuildContext context) {
    final player = AudioPlaybackService.instance;
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final path = item.audioPath;
        final isThis = path != null &&
            path.isNotEmpty &&
            player.currentPath == path;
        final playing = playingOverride ?? (isThis && player.isPlaying);
        final progress = progressOverride ??
            (isThis ? player.progress : (playing ? 0.35 : 0));

        return GestureDetector(
          onTap: () async {
            if (path == null || path.isEmpty) {
              // 无本地文件时仅切换视觉态示意
              return;
            }
            await player.play(path);
          },
          child: SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(84, 84),
                  painter: _RingPainter(
                    progress: playing || progress > 0 ? progress : 0,
                    active: playing,
                  ),
                ),
                ClipOval(
                  child: SizedBox(
                    width: 70,
                    height: 70,
                    child: ColoredBox(
                      color: AppColors.surface2,
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
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = AppColors.border;
    canvas.drawCircle(c, r, bg);

    if (progress <= 0) return;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = AppColors.accent.withValues(alpha: active ? 0.95 : 0.55);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.active != active;
}
