import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/sound_repository.dart';
import '../../services/audio_playback_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/sound_visual.dart';

/// 横向 Carousel：中央完整，左右约 18%–24% 露出。
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
  final int? placeholderIndex;
  final GlobalKey? centerCardKey;

  @override
  State<DraftTrayCarousel> createState() => _DraftTrayCarouselState();
}

class _DraftTrayCarouselState extends State<DraftTrayCarousel> {
  static const _viewportFraction = 0.60;
  late final PageController _controller;
  double _page = 0;

  @override
  void initState() {
    super.initState();
    final i = widget.selectedIndex
        .clamp(0, math.max(0, widget.items.length - 1))
        .toInt();
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
            duration: AppMotion.fast,
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
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return AnimatedOpacity(
      duration: AppMotion.fast,
      opacity: widget.dimmed ? 0.4 : 1,
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
          final scale = uiLerp(1.0, 0.90, (abs / 1.0).clamp(0.0, 1.0));
          final brightness = uiLerp(1.0, 0.62, (abs / 1.0).clamp(0.0, 1.0));
          final isCenter = index == widget.selectedIndex;
          final isPlaceholder = widget.placeholderIndex == index;

          return Transform.scale(
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
                        tintIndex: index,
                        elevated: isCenter && !widget.dimmed,
                        onTap: () => widget.onOpenDetail(item.id),
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
      width: 188,
      height: 248,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AppColors.ceramic.withValues(alpha: 0.18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
    );
  }
}

Color _cardTint(int index) {
  const tints = [
    AppColors.cardIvory,
    AppColors.cardCool,
    AppColors.cardSilver,
  ];
  return tints[index % tints.length];
}

/// 明亮实体声卡：象牙白 / 冷白 / 浅银，黑底圆形贴图。
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
  final bool? playingOverride;
  final double? progressOverride;

  String get _statusLine {
    return switch (item.status) {
      SoundStatus.drafted => 'Ready to Press',
      SoundStatus.writeFailed || SoundStatus.chainFailed => 'Ready to Press',
      SoundStatus.writing || SoundStatus.chainPending => 'Pressing',
      SoundStatus.collected => 'Sealed',
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
    final base = _cardTint(tintIndex);

    return Transform.scale(
      scale: scale,
      child: GestureDetector(
        onTap: onTap,
        onLongPressStart: onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        onLongPressEnd: onLongPressEnd,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          width: 188,
          height: 248,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: const Alignment(-0.6, -1),
              end: const Alignment(0.5, 1),
              colors: [
                Colors.white,
                base,
                Color.lerp(base, const Color(0xFFDDE2E0), 0.35)!,
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: elevated ? 0.95 : 0.55),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: elevated ? 0.38 : 0.22),
                blurRadius: elevated ? 26 : 14,
                offset: Offset(0, elevated ? 12 : 6),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.35),
                blurRadius: 0.5,
                offset: const Offset(0, -0.5),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: _CircularPlayVisual(
                  item: item,
                  size: 118,
                  playingOverride: playingOverride,
                  progressOverride: progressOverride,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  height: 1.15,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${item.category}  ·  ${formatDuration(item.durationSec)}  ·  $_dateLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                _statusLine,
                style: TextStyle(
                  color: elevated ? AppColors.accent : AppColors.inkMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
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
    this.size = 118,
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
    final inner = size - 14;

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
        ..strokeWidth = 1.5
        ..color = AppColors.silver.withValues(alpha: 0.8),
    );

    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = AppColors.accent.withValues(alpha: active ? 0.95 : 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.active != active;
}
