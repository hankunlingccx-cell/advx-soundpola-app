import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../audio/audio_features.dart';
import '../theme/app_colors.dart';

/// Strictly mirrored circular-particle streamline field.
///
/// Compute upper-right quadrant only → mirror to (−x,y)/(x,−y)/(−x,−y).
/// Particles are pure [Canvas.drawCircle] dots — never lines/capsules.
enum SoundVisualMode { idle, recording, paused, complete, playback }

const _tau = math.pi * 2;
const _streamCount = 8;
const _particlesPerStream = 36;
// 8 * 36 * 4 quadrants = 1152 dots — within 700–1400.

const _cMint = Color(0xFF63E0CB);
const _cBlue = Color(0xFF56B8FF);
const _cViolet = Color(0xFF8875FF);

double _smoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _ar(double cur, double target, double attack, double release, double dt) {
  final rate = target > cur ? attack : release;
  final k = 1.0 - math.exp(-dt / rate.clamp(0.001, 2.0));
  return cur + (target - cur) * k;
}

double _hash01(double n) {
  final x = math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - x.floorToDouble();
}

/// Fixed hidden trajectory for the upper-right quadrant (init once).
class _StreamSpec {
  const _StreamSpec({
    required this.innerX,
    required this.innerY,
    required this.horizontalLength,
    required this.archHeight,
    required this.bendX,
    required this.detailY,
    required this.phase,
    required this.sampleOffset,
    required this.outerness,
    required this.isCore,
  });

  final double innerX;
  final double innerY;
  final double horizontalLength;
  final double archHeight;
  final double bendX;
  final double detailY;
  final double phase;
  final double sampleOffset;
  final double outerness; // 0 inner → 1 outer
  final bool isCore;
}

List<_StreamSpec> _buildStreams(int seed) {
  return List.generate(_streamCount, (i) {
    double h(double k) => _hash01(seed * 0.021 + i * 13.7 + k * 4.3);
    final u = i / (_streamCount - 1);

    // Nested layers: inner closer to axes, outer more extended — not rings.
    final innerX = 0.06 + u * 0.10 + h(1) * 0.02;
    final innerY = 0.06 + u * 0.09 + h(2) * 0.02;
    final horizontalLength = 0.28 + u * 0.38 + h(3) * 0.04;
    final archHeight = 0.22 + u * 0.36 + h(4) * 0.03;

    return _StreamSpec(
      innerX: innerX,
      innerY: innerY,
      horizontalLength: horizontalLength,
      archHeight: archHeight,
      bendX: 0.018 + h(5) * 0.022 + u * 0.012,
      detailY: 0.012 + h(6) * 0.018 + u * 0.008,
      phase: h(7) * _tau,
      sampleOffset: h(8),
      outerness: u,
      isCore: i < 3,
    );
  });
}

/// Sample hidden Q1 trajectory. Returns point in unit field (x≥0, y≥0).
Offset _sampleQ1({
  required _StreamSpec s,
  required double t,
  required double time,
  required double intensity,
  required double breath,
  required double expansion,
}) {
  // Center soft space ~6–10% of subject radius.
  const centerSoft = 0.08;

  // Bend amplitude fades toward center (t→0) to prevent mid tangle.
  final centerEase = _smoothstep(0.0, 0.28, t);
  final tipEase = _smoothstep(0.0, 0.12, 1.0 - t);
  final bendLive = (1.0 + intensity * 1.1) * centerEase;

  final flowPhase = time * (0.35 + intensity * 0.55);
  final bendX = s.bendX *
      bendLive *
      math.sin(t * math.pi * 2.0 + s.phase + flowPhase * 0.4);
  final detailY = s.detailY *
      bendLive *
      math.sin(t * math.pi * 3.0 + s.phase - flowPhase * 0.3);
  final breathY =
      math.sin(t * math.pi + time * _tau / 4.4) * 0.006 * breath * centerEase;

  var x = s.innerX + t * s.horizontalLength * expansion + bendX;
  var y = s.innerY +
      math.sin(t * math.pi) * s.archHeight * expansion +
      detailY +
      breathY;

  // Soft radial clamp: keep inside subject, enforce center soft zone.
  final r = math.sqrt(x * x + y * y);
  final maxR = 0.92 * expansion;
  if (r > maxR && r > 1e-6) {
    final k = maxR / r;
    x *= k;
    y *= k;
  }
  if (r < centerSoft && r > 1e-6) {
    // Push gently outward — ordered converge, not void or knot.
    final k = centerSoft / r;
    final blend = 0.35 + 0.65 * tipEase;
    x = x * (1 - blend) + x * k * blend;
    y = y * (1 - blend) + y * k * blend;
  }

  // Strict Q1 — never cross axes (mirrors handle the rest).
  return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
}

class _SoundVisualPainter extends CustomPainter {
  _SoundVisualPainter({
    required this.streams,
    required this.mode,
    required this.intensity,
    required this.time,
    required this.breath,
    required this.quality,
    this.showProgressRing = false,
    this.progress = 0,
  });

  final List<_StreamSpec> streams;
  final SoundVisualMode mode;
  final double intensity;
  final double time;
  final double breath;
  final VisualQualityProfile quality;
  final bool showProgressRing;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final cx = size.width / 2;
    final cy = size.height / 2;
    // Subject ~72% of shorter side (68–76% band).
    final scale = side * (0.72 + intensity * 0.015) * quality.resolutionScale;

    final expansion = 1.0 + intensity * 0.06;
    final flowSpeed = 0.07 + intensity * 0.55;
    final radiusScale = 1.0 + intensity * 0.22; // max +22% — never stretch
    final bright = (0.74 + intensity * 0.26).clamp(0.6, 1.12);

    final streamLimit = switch (quality.tier) {
      VisualQuality.high => _streamCount,
      VisualQuality.medium => 7,
      VisualQuality.low => 5,
    };
    final particleStep = quality.tier == VisualQuality.low ? 2 : 1;

    final paint = Paint()..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(cx, cy);

    for (var si = 0; si < streamLimit; si++) {
      final s = streams[si];
      final n = _particlesPerStream;
      // Shared progress for all 4 mirrored copies — no per-quadrant phase.
      final flow = time * flowSpeed * (0.9 + s.outerness * 0.15) + s.sampleOffset;

      for (var p = 0; p < n; p += particleStep) {
        final t = (p / n + flow) % 1.0;
        final pos = _sampleQ1(
          s: s,
          t: t,
          time: time,
          intensity: intensity,
          breath: breath,
          expansion: expansion,
        );

        // Color shared across mirrors.
        Color col;
        if (s.outerness > 0.75 && intensity > 0.5) {
          col = Color.lerp(
            _cBlue,
            _cViolet,
            ((intensity - 0.5) / 0.5 * 0.5).clamp(0.0, 0.5),
          )!;
        } else if (s.outerness > 0.55) {
          col = Color.lerp(_cMint, _cBlue, 0.28 + s.outerness * 0.2)!;
        } else {
          col = _cMint;
        }

        // Mid layers clearest; outer slightly dimmer; density lower outward.
        final midBoost = (1.0 - (s.outerness - 0.35).abs() * 1.4).clamp(0.0, 1.0);
        final alpha = ((s.isCore ? 0.72 : 0.52) +
                midBoost * 0.18 -
                s.outerness * 0.14 +
                intensity * 0.1) *
            bright;
        final a = alpha.clamp(0.14, 0.92);

        final baseR = s.isCore
            ? (1.7 + s.outerness * 0.3)
            : (0.95 + (1.0 - s.outerness) * 0.55);
        final radius = (baseR * radiusScale).clamp(0.8, 2.5);

        paint.color = col.withValues(alpha: a);

        final x = pos.dx * scale;
        final y = pos.dy * scale;

        // Strict dual-axis mirror — identical r / color / alpha / phase.
        canvas.drawCircle(Offset(x, y), radius, paint);
        canvas.drawCircle(Offset(-x, y), radius, paint);
        canvas.drawCircle(Offset(x, -y), radius, paint);
        canvas.drawCircle(Offset(-x, -y), radius, paint);
      }
    }

    // Sparse low-alpha center connectors (dots only, shared mirrors).
    if (quality.tier != VisualQuality.low) {
      final linkN = 5;
      for (var i = 0; i < linkN; i++) {
        final u = (i + 0.5) / linkN;
        final ang = u * (math.pi * 0.5);
        final r = 0.055 + 0.025 * math.sin(time * _tau / 5.0 + u * 2);
        final x = math.cos(ang) * r * scale;
        final y = math.sin(ang) * r * scale;
        paint.color = _cMint.withValues(alpha: 0.18 * bright);
        final rr = 0.9 * radiusScale;
        canvas.drawCircle(Offset(x, y), rr, paint);
        canvas.drawCircle(Offset(-x, y), rr, paint);
        canvas.drawCircle(Offset(x, -y), rr, paint);
        canvas.drawCircle(Offset(-x, -y), rr, paint);
      }
    }

    canvas.restore();

    if (showProgressRing) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: side * 0.46),
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0, 1),
        false,
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SoundVisualPainter old) =>
      old.time != time ||
      old.breath != breath ||
      old.intensity != intensity ||
      old.mode != mode ||
      old.quality.tier != quality.tier ||
      old.progress != progress;
}

class SoundVisualCanvas extends StatefulWidget {
  const SoundVisualCanvas({
    super.key,
    required this.seed,
    this.active = false,
    this.dark = true,
    this.mode,
    this.amplitude = 0.2,
    this.features,
    this.showProgressRing = false,
    this.progress = 0,
  });

  final int seed;
  final bool active;
  final bool dark;
  final SoundVisualMode? mode;
  final double amplitude;
  final ValueListenable<AudioFeatures>? features;
  final bool showProgressRing;
  final double progress;

  @override
  State<SoundVisualCanvas> createState() => _SoundVisualCanvasState();
}

class _SoundVisualCanvasState extends State<SoundVisualCanvas>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final List<_StreamSpec> _streams;

  final _start = DateTime.now();
  Duration _lastElapsed = Duration.zero;
  double _smoothedVolume = 0.12;
  double _intensity = 0.0;
  VisualQuality _tier = VisualQuality.high;
  final _frameTimes = <double>[];
  int _paintEpoch = 0;
  bool _paintScheduled = false;

  SoundVisualMode get _mode =>
      widget.mode ??
      (widget.active ? SoundVisualMode.recording : SoundVisualMode.idle);

  bool get _isLive =>
      _mode == SoundVisualMode.recording || _mode == SoundVisualMode.playback;

  VisualQualityProfile get _profile {
    if (_mode == SoundVisualMode.idle ||
        _mode == SoundVisualMode.complete ||
        _mode == SoundVisualMode.paused) {
      return VisualQualityProfile.idle;
    }
    return VisualQualityProfile.forTier(_tier);
  }

  @override
  void initState() {
    super.initState();
    _streams = _buildStreams(widget.seed);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _adaptQuality(double dt) {
    if (!_isLive) {
      _tier = VisualQuality.medium;
      return;
    }
    _frameTimes.add(dt);
    if (_frameTimes.length > 30) _frameTimes.removeAt(0);
    if (_frameTimes.length < 12) return;
    final avg = _frameTimes.reduce((a, b) => a + b) / _frameTimes.length;
    if (avg > 1 / 45) {
      if (_tier == VisualQuality.high) {
        _tier = VisualQuality.medium;
      } else if (_tier == VisualQuality.medium) {
        _tier = VisualQuality.low;
      }
    } else if (avg < 1 / 55 && _tier != VisualQuality.high) {
      _tier = _tier == VisualQuality.low
          ? VisualQuality.medium
          : VisualQuality.high;
    }
  }

  double _rawVolume() {
    final f = widget.features?.value;
    if (f != null) return f.rms.clamp(0.0, 1.0);
    return widget.amplitude.clamp(0.0, 1.0);
  }

  void _onTick(Duration elapsed) {
    final t = _mode == SoundVisualMode.complete
        ? 5.0 + (widget.seed % 11) * 0.07
        : elapsed.inMilliseconds / 1000.0;
    final dt = _lastElapsed == Duration.zero
        ? 1 / 60
        : ((elapsed - _lastElapsed).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastElapsed = elapsed;

    _adaptQuality(dt);

    final volTarget = _isLive
        ? _rawVolume()
        : (_mode == SoundVisualMode.paused
            ? _smoothedVolume * 0.4
            : 0.1 + 0.05 * (0.5 + 0.5 * math.sin(t * _tau / 5.0)));
    _smoothedVolume = _ar(_smoothedVolume, volTarget, 0.11, 0.48, dt);
    _intensity = _smoothstep(0.06, 0.72, _smoothedVolume);

    final profile = _profile;
    if (!_isLive && _mode != SoundVisualMode.complete) {
      final frame = (t * profile.targetFps).floor();
      if (frame == _paintEpoch) return;
      _paintEpoch = frame;
    }

    _schedulePaint();
  }

  void _schedulePaint() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final unsafe = phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.persistentCallbacks;
    if (unsafe) {
      if (_paintScheduled) return;
      _paintScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _paintScheduled = false;
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final t = _mode == SoundVisualMode.complete
        ? 5.0 + (widget.seed % 11) * 0.07
        : DateTime.now().difference(_start).inMilliseconds / 1000.0;
    final breath =
        reduce ? 0.5 : 0.5 + 0.5 * math.sin(t * _tau / (_isLive ? 3.8 : 4.5));

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        final width = switch ((maxW.isFinite, maxH.isFinite)) {
          (true, true) => math.min(maxW * 0.96, maxH * 0.98),
          (true, false) => maxW * 0.96,
          (false, true) => maxH * 0.9,
          _ => 300.0,
        };
        final height = width.clamp(0.0, maxH.isFinite ? maxH : width);
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _SoundVisualPainter(
                  streams: _streams,
                  mode: reduce ? SoundVisualMode.complete : _mode,
                  intensity: reduce ? 0.12 : _intensity,
                  time: reduce ? t * 0.15 : t,
                  breath: breath,
                  quality: _profile,
                  showProgressRing: widget.showProgressRing,
                  progress: widget.progress,
                ),
                size: Size(width, height),
              ),
            ),
          ),
        );
      },
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
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: const Size(180, 180),
            painter: _NfcRipplePainter(
              t: widget.active ? _controller.value : 0.4,
            ),
          );
        },
      ),
    );
  }
}

class _NfcRipplePainter extends CustomPainter {
  _NfcRipplePainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1.0;
      final r = size.shortestSide * 0.15 + size.shortestSide * 0.35 * phase;
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = AppColors.accent.withValues(alpha: (1 - phase) * 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
    canvas.drawCircle(
      Offset(cx, cy),
      16,
      Paint()..color = AppColors.accent.withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(covariant _NfcRipplePainter oldDelegate) =>
      oldDelegate.t != t;
}
