import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SoundVisualPainter extends CustomPainter {
  SoundVisualPainter({
    required this.seed,
    required this.active,
    required this.animation,
    this.dark = false,
    this.showProgressRing = false,
    this.progress = 0,
  });

  final int seed;
  final bool active;
  final double animation;
  final bool dark;
  final bool showProgressRing;
  final double progress;

  static const _palette = [
    AppColors.primary500,
    AppColors.primary300,
    AppColors.primary600,
    AppColors.primary700,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(size.width, size.height) / 2;
    final alpha = dark ? 0.55 : 0.42;
    final breath = active
        ? 0.94 + 0.12 * math.sin(animation * math.pi * 2)
        : 0.94 + 0.06 * math.sin(animation * math.pi * 2);
    final spin = animation * 360;

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.primary500.withValues(alpha: active ? 0.32 : 0.16),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));
    canvas.drawCircle(Offset(cx, cy), radius, glow);

    final count = 16 + seed % 10;
    for (var i = 0; i < count; i++) {
      final angle = (spin + i * (360 / count) + seed % 40) * math.pi / 180;
      final layer = 0.2 + (i % 5) * 0.11;
      final wobble = 1 + 0.1 * math.sin(angle * (active ? 3 : 1.5));
      final r = radius * layer * breath * wobble;
      final x = cx + math.cos(angle) * r;
      final y = cy + math.sin(angle) * r;
      final mirrorX = cx - math.cos(angle) * r;
      final color = _palette[i % _palette.length].withValues(alpha: alpha);
      final dot = active ? 4.2 : 3.0;
      canvas.drawCircle(Offset(x, y), dot, Paint()..color = color);
      canvas.drawCircle(Offset(mirrorX, y), dot, Paint()..color = color);
    }

    canvas.drawCircle(
      Offset(cx, cy),
      radius * 0.16 * breath,
      Paint()
        ..color = AppColors.primary500.withValues(alpha: dark ? 0.4 : 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    if (showProgressRing) {
      final ringRect = Rect.fromCircle(center: Offset(cx, cy), radius: radius * 0.92);
      canvas.drawArc(
        ringRect,
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0, 1),
        false,
        Paint()
          ..color = AppColors.primary500
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SoundVisualPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.active != active ||
      oldDelegate.progress != progress;
}

class SoundVisualCanvas extends StatefulWidget {
  const SoundVisualCanvas({
    super.key,
    required this.seed,
    this.active = false,
    this.dark = false,
    this.showProgressRing = false,
    this.progress = 0,
  });

  final int seed;
  final bool active;
  final bool dark;
  final bool showProgressRing;
  final double progress;

  @override
  State<SoundVisualCanvas> createState() => _SoundVisualCanvasState();
}

class _SoundVisualCanvasState extends State<SoundVisualCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.active ? 6500 : 18000),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant SoundVisualCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _controller.duration =
          Duration(milliseconds: widget.active ? 6500 : 18000);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: SoundVisualPainter(
            seed: widget.seed,
            active: widget.active,
            animation: _controller.value,
            dark: widget.dark,
            showProgressRing: widget.showProgressRing,
            progress: widget.progress,
          ),
          child: child,
        );
      },
      child: const SizedBox.expand(),
    );
  }
}

class NfcRippleVisual extends StatefulWidget {
  const NfcRippleVisual({super.key, this.active = true});
  final bool active;

  @override
  State<NfcRippleVisual> createState() => _NfcRippleVisualState();
}

class _NfcRippleVisualState extends State<NfcRippleVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = widget.active ? 0.7 + 0.3 * _controller.value : 0.95;
        return CustomPaint(
          size: const Size(180, 180),
          painter: _NfcRipplePainter(pulse: pulse),
        );
      },
    );
  }
}

class _NfcRipplePainter extends CustomPainter {
  _NfcRipplePainter({required this.pulse});
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    for (var i = 1; i <= 3; i++) {
      final r = size.shortestSide * 0.22 * i * pulse;
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = AppColors.primary500.withValues(alpha: 0.18 / i)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    canvas.drawCircle(
      Offset(cx, cy),
      18,
      Paint()..color = AppColors.primary500.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _NfcRipplePainter oldDelegate) =>
      oldDelegate.pulse != pulse;
}
