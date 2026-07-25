import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/sound_repository.dart';
import '../../services/audio_playback_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/sound_visual.dart';

/// 横向 Carousel：中央完整，左右各露出约 18%–24%。
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
  /// 约 20% 左右露出。
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
      opacity: widget.dimmed ? 0.38 : 1,
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
          final brightness = uiLerp(1.0, 0.48, (abs / 1.0).clamp(0.0, 1.0));
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
    return CustomPaint(
      size: const Size(188, 248),
      painter: _SampleFramePainter(
        elevated: false,
        placeholder: true,
      ),
    );
  }
}

/// 未封存声音样本卡：石墨底 + 四角定位 + 断线刻度，非 Material 圆角卡。
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
      SoundStatus.drafted => 'READY TO PRESS',
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
    const w = 188.0;
    const h = 248.0;

    return Transform.scale(
      scale: scale,
      child: GestureDetector(
        onTap: onTap,
        onLongPressStart: onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        onLongPressEnd: onLongPressEnd,
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: [
              CustomPaint(
                size: const Size(w, h),
                painter: _SampleFramePainter(elevated: elevated),
              ),
              Padding(
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
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 18,
                        height: 1.15,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${item.category}  ·  ${formatDuration(item.durationSec)}  ·  $_dateLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _statusLine,
                      style: TextStyle(
                        fontFamily: 'Courier',
                        color: elevated
                            ? AppColors.accent.withValues(alpha: 0.88)
                            : AppColors.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'RARITY UNKNOWN',
                      style: TextStyle(
                        fontFamily: 'Courier',
                        color: AppColors.textTertiary,
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SampleFramePainter extends CustomPainter {
  _SampleFramePainter({required this.elevated, this.placeholder = false});

  final bool elevated;
  final bool placeholder;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );

    if (placeholder) {
      canvas.drawRRect(
        r,
        Paint()..color = AppColors.graphite.withValues(alpha: 0.35),
      );
      _drawCorners(canvas, size, AppColors.structure.withValues(alpha: 0.55));
      return;
    }

    canvas.drawRRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width * 0.5, 0),
          Offset(size.width * 0.5, size.height),
          [
            elevated ? const Color(0xFF151B19) : AppColors.graphite,
            const Color(0xFF0A0E0D),
          ],
        ),
    );

    // 结构灰细边，非完整青色描边
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = elevated
            ? AppColors.structure.withValues(alpha: 0.95)
            : AppColors.structure.withValues(alpha: 0.55),
    );

    _drawCorners(
      canvas,
      size,
      elevated
          ? AppColors.accent.withValues(alpha: 0.55)
          : AppColors.structure,
    );

    // 顶部断线刻度
    final y = 10.0;
    final paint = Paint()
      ..color = AppColors.structure.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(22, y), Offset(size.width * 0.28, y), paint);
    canvas.drawLine(
      Offset(size.width * 0.72, y),
      Offset(size.width - 22, y),
      paint,
    );

    // 底部微型编号轨
    final by = size.height - 10;
    for (var i = 0; i < 9; i++) {
      final t = i / 8;
      final x = ui.lerpDouble(20, size.width - 20, t)!;
      canvas.drawLine(
        Offset(x, by - (i % 3 == 0 ? 3.5 : 2)),
        Offset(x, by + (i % 3 == 0 ? 3.5 : 2)),
        Paint()
          ..color = AppColors.structure.withValues(alpha: 0.55)
          ..strokeWidth = 0.9,
      );
    }

    if (elevated) {
      canvas.drawRRect(
        r,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.01)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
  }

  void _drawCorners(Canvas canvas, Size size, Color color) {
    const len = 10.0;
    const m = 6.0;
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    // TL
    canvas.drawLine(const Offset(m, m + len), const Offset(m, m), p);
    canvas.drawLine(const Offset(m, m), const Offset(m + len, m), p);
    // TR
    canvas.drawLine(
      Offset(size.width - m - len, m),
      Offset(size.width - m, m),
      p,
    );
    canvas.drawLine(
      Offset(size.width - m, m),
      Offset(size.width - m, m + len),
      p,
    );
    // BL
    canvas.drawLine(
      Offset(m, size.height - m - len),
      Offset(m, size.height - m),
      p,
    );
    canvas.drawLine(
      Offset(m, size.height - m),
      Offset(m + len, size.height - m),
      p,
    );
    // BR
    canvas.drawLine(
      Offset(size.width - m - len, size.height - m),
      Offset(size.width - m, size.height - m),
      p,
    );
    canvas.drawLine(
      Offset(size.width - m, size.height - m - len),
      Offset(size.width - m, size.height - m),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _SampleFramePainter old) =>
      old.elevated != elevated || old.placeholder != placeholder;
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
                      color: AppColors.device,
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
        ..strokeWidth = 1.6
        ..color = AppColors.structure,
    );

    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = AppColors.accent.withValues(alpha: active ? 0.95 : 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.active != active;
}
