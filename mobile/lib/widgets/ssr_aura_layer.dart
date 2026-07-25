import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/disc_rarity.dart';
import '../theme/app_colors.dart';

/// SSR 独占外围效果层：边缘微粒 + 可选视差偏移。
/// 布局尺寸仍为 [size]，粒子可画到圆缘外（父级需 `clipBehavior: Clip.none`）。
class SsrAuraLayer extends StatefulWidget {
  const SsrAuraLayer({
    super.key,
    required this.size,
    required this.enabled,
    this.playing = false,
    this.energy = 0.2,
    this.intensity = 1.0,
    this.parallax = Offset.zero,
    this.burst = false,
    this.child,
  });

  final double size;
  final bool enabled;
  final bool playing;
  final double energy;
  final double intensity;
  final Offset parallax;
  final bool burst;
  final Widget? child;

  static bool isSsr(DiscRarity? rarity) => rarity == DiscRarity.ssr;

  @override
  State<SsrAuraLayer> createState() => _SsrAuraLayerState();
}

class _SsrAuraLayerState extends State<SsrAuraLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  final _rng = math.Random(63);
  late List<_SsrParticle> _particles;
  double _burstT = 0;

  @override
  void initState() {
    super.initState();
    _particles = _spawn(count: 12);
    _ticker = createTicker(_onTick);
    if (widget.enabled) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant SsrAuraLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_ticker.isActive) {
      _ticker.start();
    } else if (!widget.enabled && _ticker.isActive) {
      _ticker.stop();
    }
    if (widget.burst && !oldWidget.burst) {
      _burstT = 1;
      _particles = [..._particles, ..._spawn(count: 20, burst: true)];
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _elapsed).inMicroseconds / 1e6;
    _elapsed = elapsed;
    if (dt <= 0 || dt > 0.05) return;

    final energy =
        widget.playing ? (0.35 + widget.energy.clamp(0.0, 1.0) * 0.65) : 0.22;
    final lifeScale = widget.intensity.clamp(0.0, 1.0);

    for (final p in _particles) {
      p.age += dt * (widget.playing ? 1.15 + energy * 0.4 : 0.85);
      p.angle += p.spin * dt;
      p.radius += p.outSpeed * dt * (0.7 + energy);
      if (p.age >= p.life) _respawn(p);
    }

    if (_burstT > 0) {
      _burstT = (_burstT - dt * 1.6).clamp(0.0, 1.0);
    }

    final target = widget.burst || _burstT > 0.05
        ? 26
        : ((widget.playing ? 14 : 9) * lifeScale);
    final want = target.round().clamp(2, 26);
    if (_particles.length > want + 4) {
      _particles.removeRange(want, _particles.length);
    } else if (_particles.length < want) {
      _particles.addAll(_spawn(count: want - _particles.length));
    }

    if (mounted) setState(() {});
  }

  List<_SsrParticle> _spawn({required int count, bool burst = false}) {
    final rim = widget.size / 2;
    return List.generate(count, (_) {
      return _SsrParticle(
        angle: _rng.nextDouble() * math.pi * 2,
        radius: rim + _rng.nextDouble() * (burst ? 5 : 1.5),
        size: burst
            ? 1.5 + _rng.nextDouble() * 2.0
            : 0.9 + _rng.nextDouble() * 1.5,
        life: burst
            ? 0.4 + _rng.nextDouble() * 0.35
            : 1.5 + _rng.nextDouble() * 2.0,
        age: burst ? 0 : _rng.nextDouble() * 1.0,
        spin: (_rng.nextDouble() - 0.5) * (burst ? 2.2 : 0.85),
        outSpeed: burst
            ? 26 + _rng.nextDouble() * 36
            : 3.5 + _rng.nextDouble() * 9,
        tint: _rng.nextBool()
            ? AppColors.accent
            : (_rng.nextBool()
                ? const Color(0xFF4FA9E8)
                : const Color(0xFFD879C8)),
      );
    });
  }

  void _respawn(_SsrParticle p) {
    final rim = widget.size / 2;
    p
      ..angle = _rng.nextDouble() * math.pi * 2
      ..radius = rim + _rng.nextDouble() * 1.5
      ..size = 0.9 + _rng.nextDouble() * 1.5
      ..life = 1.5 + _rng.nextDouble() * 2.0
      ..age = 0
      ..spin = (_rng.nextDouble() - 0.5) * 0.85
      ..outSpeed = 3.5 + _rng.nextDouble() * 9
      ..tint = _rng.nextBool()
          ? AppColors.accent
          : (_rng.nextBool()
              ? const Color(0xFF4FA9E8)
              : const Color(0xFFD879C8));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disc = SizedBox(
      width: widget.size,
      height: widget.size,
      child: widget.child,
    );

    if (!widget.enabled) {
      return disc;
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: widget.parallax,
            child: disc,
          ),
          // 镭射高光轻微反相视差，增强薄片折射感
          if (widget.parallax != Offset.zero)
            IgnorePointer(
              child: Transform.translate(
                offset: -widget.parallax * 0.55,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(
                        (widget.parallax.dx / 4).clamp(-0.4, 0.4),
                        (widget.parallax.dy / 4).clamp(-0.4, 0.4),
                      ),
                      colors: [
                        Colors.white.withValues(alpha: 0.10),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.65],
                    ),
                  ),
                  child: SizedBox(width: widget.size, height: widget.size),
                ),
              ),
            ),
          IgnorePointer(
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _SsrParticlePainter(
                particles: _particles,
                intensity: widget.intensity.clamp(0.05, 1.0),
                burstBoost: _burstT,
                playing: widget.playing,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SsrParticle {
  _SsrParticle({
    required this.angle,
    required this.radius,
    required this.size,
    required this.life,
    required this.age,
    required this.spin,
    required this.outSpeed,
    required this.tint,
  });

  double angle;
  double radius;
  double size;
  double life;
  double age;
  double spin;
  double outSpeed;
  Color tint;
}

class _SsrParticlePainter extends CustomPainter {
  _SsrParticlePainter({
    required this.particles,
    required this.intensity,
    required this.burstBoost,
    required this.playing,
  });

  final List<_SsrParticle> particles;
  final double intensity;
  final double burstBoost;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final t = (p.age / p.life).clamp(0.0, 1.0);
      final fade = (1 - t) * intensity * (playing ? 1.0 : 0.72);
      final alpha = (0.12 + fade * 0.55 + burstBoost * 0.28).clamp(0.0, 0.85);
      if (alpha < 0.02) continue;
      final pos = Offset(
        c.dx + math.cos(p.angle) * p.radius,
        c.dy + math.sin(p.angle) * p.radius,
      );
      paint.color = p.tint.withValues(alpha: alpha);
      canvas.drawCircle(pos, p.size * (1 + burstBoost * 0.35), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SsrParticlePainter oldDelegate) => true;
}

/// 堆叠滑动位移 → SSR 视差（约 2～4px）。
Offset ssrParallaxFromDelta(double pageDelta, {double maxPx = 3.5}) {
  final x = (pageDelta * maxPx).clamp(-maxPx, maxPx);
  final y = (pageDelta.abs() * maxPx * 0.35).clamp(0.0, maxPx * 0.5);
  return Offset(-x, y);
}
