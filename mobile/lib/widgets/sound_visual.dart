import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../audio/audio_features.dart';
import '../theme/app_colors.dart';

/// Ordered mirrored circular-particle field.
///
/// One master Q1 curve → normal-offset nested streams → dual-axis mirror.
/// Shape driven by fast volume envelope (not canvas scale / brightness alone).
enum SoundVisualMode { idle, recording, paused, complete, playback }

const _tau = math.pi * 2;
const _streamCount = 6;
const _particlesPerStream = 48;
// 6 * 48 * 4 = 1152
const _arcTableSteps = 96;

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

/// Cumulative normal offset in unit field (~dp mapped for ~300px stage).
/// Inner 7–10dp · mid 10–14 · outer 14–20 — smooth growth.
double _bundleOffset(int streamIndex, double opening) {
  // Approx: 1 unit ≈ half-subject ≈ 0.36 * side; use ~110 unit-px at scale.
  // Spacing expressed in unit-field directly.
  var sum = 0.0;
  for (var i = 0; i < streamIndex; i++) {
    final u = i / math.max(1, _streamCount - 1);
    final gap = 0.026 + u * 0.022; // ~inner→outer growth
    sum += gap;
  }
  return sum * opening;
}

class _ShapeParams {
  const _ShapeParams({
    required this.expansion,
    required this.opening,
    required this.bending,
    required this.outerReach,
    required this.innerPull,
  });

  final double expansion;
  final double opening;
  final double bending;
  final double outerReach;
  final double innerPull;
}

_ShapeParams _shapeFromFast(double fast) {
  // Priority: contour > opening > bend > (speed/brightness elsewhere)
  return _ShapeParams(
    expansion: 0.92 + fast * 0.14,
    opening: 1.0 + fast * 0.55,
    bending: 0.35 + fast * 1.05,
    outerReach: 0.0 + fast * 0.11,
    innerPull: 0.035 - fast * 0.022,
  );
}

/// Master Q1 curve: rounded-square quarter arc (no ears / eyes / nose).
Offset _masterAt({
  required double t,
  required double time,
  required _ShapeParams shape,
  required double breath,
  required double slow,
}) {
  // Avoid exact axes → no isolated vertical particle chains.
  final theta = (0.07 + t * 0.86) * (math.pi * 0.5);
  // p∈(0.55,1): lower = squarer. 0.72 = soft rounded square, not circle rings.
  const p = 0.72;

  var r = (0.50 + shape.outerReach) * shape.expansion;
  // Shared continuous bend field — all streams inherit via normal offset.
  final bend = shape.bending;
  final w1 = math.sin(theta * 2.0 + time * 0.65) * 0.028 * bend;
  final w2 = math.sin(theta * 3.5 - time * 0.4) * 0.012 * bend;
  // Fade bend near ends so tips don't form sharp corners / ears.
  final tipFade = _smoothstep(0.0, 0.12, t) * _smoothstep(0.0, 0.12, 1.0 - t);
  r *= 1.0 + (w1 + w2) * tipFade;
  r *= 1.0 + breath * 0.01 * (0.4 + 0.6 * slow);

  final c = math.cos(theta);
  final s = math.sin(theta);
  var x = r * math.pow(c.abs(), p).toDouble();
  var y = r * math.pow(s.abs(), p).toDouble();

  // Soft center breath zone 4–7% — ordered converge, no void / knot.
  const soft = 0.055;
  final len = math.sqrt(x * x + y * y) + 1e-8;
  if (len < soft) {
    final k = soft / len;
    x *= k;
    y *= k;
  }
  return Offset(x.clamp(0.0, 1.05), y.clamp(0.0, 1.05));
}

Offset _streamPoint({
  required int streamIndex,
  required double t,
  required double time,
  required _ShapeParams shape,
  required double breath,
  required double slow,
}) {
  final a = _masterAt(
    t: t,
    time: time,
    shape: shape,
    breath: breath,
    slow: slow,
  );
  final b = _masterAt(
    t: (t + 0.004).clamp(0.0, 1.0),
    time: time,
    shape: shape,
    breath: breath,
    slow: slow,
  );
  var tx = b.dx - a.dx;
  var ty = b.dy - a.dy;
  final tLen = math.sqrt(tx * tx + ty * ty) + 1e-8;
  tx /= tLen;
  ty /= tLen;
  // Outward-ish normal (away from origin side of tangent) — prevents crossing.
  var nx = -ty;
  var ny = tx;
  // Flip so normal points roughly away from origin (nested expand outward).
  if (nx * a.dx + ny * a.dy < 0) {
    nx = -nx;
    ny = -ny;
  }

  final u = streamIndex / (_streamCount - 1);
  var offset = _bundleOffset(streamIndex, shape.opening);
  // Inner contraction when quiet; outer gets more of outerReach.
  offset += shape.outerReach * u * 0.06;
  offset -= shape.innerPull * (1.0 - u);

  var x = a.dx + nx * offset;
  var y = a.dy + ny * offset;

  // Keep Q1 and soft center.
  const soft = 0.05;
  final len = math.sqrt(x * x + y * y) + 1e-8;
  if (len < soft) {
    final k = soft / len;
    x *= k;
    y *= k;
  }
  return Offset(x.clamp(0.0, 1.1), y.clamp(0.0, 1.1));
}

/// Arc-length uniform parameter table for one stream at current shape.
List<double> _arcLengthTs({
  required int streamIndex,
  required double time,
  required _ShapeParams shape,
  required double breath,
  required double slow,
}) {
  final pts = List<Offset>.generate(_arcTableSteps + 1, (i) {
    final t = i / _arcTableSteps;
    return _streamPoint(
      streamIndex: streamIndex,
      t: t,
      time: time,
      shape: shape,
      breath: breath,
      slow: slow,
    );
  });
  final cum = List<double>.filled(_arcTableSteps + 1, 0);
  for (var i = 1; i <= _arcTableSteps; i++) {
    cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).distance;
  }
  final total = cum.last;
  if (total < 1e-6) {
    return List<double>.generate(_particlesPerStream, (j) => j / _particlesPerStream);
  }
  // Inner denser: slight bias toward ends? Spec: inner streams denser spacing
  // via more particles feel — we keep equal arc on each stream; outer streams
  // are longer so same count = slightly sparser visually. Good.
  return List<double>.generate(_particlesPerStream, (j) {
    final target = (j / _particlesPerStream) * total;
    // Binary search cum
    var lo = 0;
    var hi = _arcTableSteps;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (cum[mid] < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final i = lo.clamp(1, _arcTableSteps);
    final c0 = cum[i - 1];
    final c1 = cum[i];
    final seg = (c1 - c0).clamp(1e-8, double.infinity);
    final f = ((target - c0) / seg).clamp(0.0, 1.0);
    return ((i - 1) + f) / _arcTableSteps;
  });
}

class _VisualFrame extends ChangeNotifier {
  double fast = 0;
  double slow = 0;
  double time = 0;
  double breath = 0.5;
  double flowPhase = 0;
  SoundVisualMode mode = SoundVisualMode.idle;
  VisualQualityProfile quality = VisualQualityProfile.idle;
  bool showProgressRing = false;
  double progress = 0;

  void bump() => notifyListeners();
}

class _SoundVisualPainter extends CustomPainter {
  _SoundVisualPainter(this.frame) : super(repaint: frame);

  final _VisualFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = side * 0.72 * frame.quality.resolutionScale;

    final fast = frame.fast;
    final slow = frame.slow;
    final time = frame.time;
    final breath = frame.breath;
    final flowPhase = frame.flowPhase;
    final shape = _shapeFromFast(fast);
    final bright = (0.78 + slow * 0.18).clamp(0.65, 1.05);
    final radiusMul = 1.0 + fast * 0.12;

    final streamLimit = switch (frame.quality.tier) {
      VisualQuality.high => _streamCount,
      VisualQuality.medium => 5,
      VisualQuality.low => 4,
    };
    final particleStep = frame.quality.tier == VisualQuality.low ? 2 : 1;

    final paint = Paint()..style = PaintingStyle.fill;
    canvas.save();
    canvas.translate(cx, cy);

    for (var si = 0; si < streamLimit; si++) {
      final u = si / (_streamCount - 1);
      final ts = _arcLengthTs(
        streamIndex: si,
        time: time,
        shape: shape,
        breath: breath,
        slow: slow,
      );

      final Color col;
      final double baseAlpha;
      final double baseR;
      if (u < 0.28) {
        col = _cMint;
        baseAlpha = 0.88;
        baseR = 1.15;
      } else if (u < 0.62) {
        col = Color.lerp(_cMint, _cBlue, 0.35 + slow * 0.15)!;
        baseAlpha = 0.68;
        baseR = 0.95;
      } else {
        col = Color.lerp(_cBlue, _cViolet, 0.25 + fast * 0.35)!;
        baseAlpha = 0.38;
        baseR = 0.72;
      }

      final layerSpeed = 0.85 + u * 0.2;
      final n = ts.length;

      for (var p = 0; p < n; p += particleStep) {
        final idx = (p + (flowPhase * n * layerSpeed).floor()) % n;
        final t = ts[idx];
        final pos = _streamPoint(
          streamIndex: si,
          t: t,
          time: time,
          shape: shape,
          breath: breath,
          slow: slow,
        );

        final alpha = (baseAlpha * bright * (0.92 + 0.08 * (1.0 - u)))
            .clamp(0.16, 0.95);
        final radius = (baseR * radiusMul).clamp(0.55, 1.6);

        paint.color = col.withValues(alpha: alpha);
        final x = pos.dx * scale;
        final y = pos.dy * scale;
        canvas.drawCircle(Offset(x, y), radius, paint);
        canvas.drawCircle(Offset(-x, y), radius, paint);
        canvas.drawCircle(Offset(x, -y), radius, paint);
        canvas.drawCircle(Offset(-x, -y), radius, paint);
      }
    }

    if (frame.quality.tier != VisualQuality.low) {
      for (var i = 0; i < 4; i++) {
        final ang = (i + 0.5) / 4 * (math.pi * 0.5);
        final r = 0.042 + 0.01 * math.sin(time * _tau / 5.2 + i);
        final x = math.cos(ang) * r * scale;
        final y = math.sin(ang) * r * scale;
        paint.color = _cMint.withValues(alpha: 0.2 * bright);
        const rr = 0.65;
        canvas.drawCircle(Offset(x, y), rr, paint);
        canvas.drawCircle(Offset(-x, y), rr, paint);
        canvas.drawCircle(Offset(x, -y), rr, paint);
        canvas.drawCircle(Offset(-x, -y), rr, paint);
      }
    }

    canvas.restore();

    if (frame.showProgressRing) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: side * 0.46),
        -math.pi / 2,
        math.pi * 2 * frame.progress.clamp(0, 1),
        false,
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SoundVisualPainter old) => false;
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
    this.liveVolume,
    this.showProgressRing = false,
    this.progress = 0,
  });

  final int seed;
  final bool active;
  final bool dark;
  final SoundVisualMode? mode;
  final double amplitude;
  final ValueListenable<AudioFeatures>? features;
  /// Raw 0–1 volume at ~20–50ms for fast shape envelope (preferred).
  final ValueListenable<double>? liveVolume;
  final bool showProgressRing;
  final double progress;

  @override
  State<SoundVisualCanvas> createState() => _SoundVisualCanvasState();
}

class _SoundVisualCanvasState extends State<SoundVisualCanvas>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _frame = _VisualFrame();
  late final _SoundVisualPainter _painter;

  Duration _lastElapsed = Duration.zero;
  double _rawTarget = 0.12;
  VisualQuality _tier = VisualQuality.high;
  final _frameTimes = <double>[];
  int _paintEpoch = 0;

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
    _painter = _SoundVisualPainter(_frame);
    widget.features?.addListener(_onFeatures);
    widget.liveVolume?.addListener(_onLiveVolume);
    _syncRawTarget();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant SoundVisualCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.features != widget.features) {
      oldWidget.features?.removeListener(_onFeatures);
      widget.features?.addListener(_onFeatures);
    }
    if (oldWidget.liveVolume != widget.liveVolume) {
      oldWidget.liveVolume?.removeListener(_onLiveVolume);
      widget.liveVolume?.addListener(_onLiveVolume);
    }
    _frame.showProgressRing = widget.showProgressRing;
    _frame.progress = widget.progress;
  }

  @override
  void dispose() {
    widget.features?.removeListener(_onFeatures);
    widget.liveVolume?.removeListener(_onLiveVolume);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onFeatures() => _syncRawTarget();
  void _onLiveVolume() => _syncRawTarget();

  void _syncRawTarget() {
    if (widget.liveVolume != null) {
      _rawTarget = widget.liveVolume!.value.clamp(0.0, 1.0);
      return;
    }
    final f = widget.features?.value;
    if (f != null) {
      _rawTarget = f.rms.clamp(0.0, 1.0);
      return;
    }
    _rawTarget = widget.amplitude.clamp(0.0, 1.0);
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

  void _onTick(Duration elapsed) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final t = _mode == SoundVisualMode.complete
        ? 5.0 + (widget.seed % 11) * 0.07
        : elapsed.inMilliseconds / 1000.0;
    final dt = _lastElapsed == Duration.zero
        ? 1 / 60
        : ((elapsed - _lastElapsed).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastElapsed = elapsed;

    _adaptQuality(dt);
    _syncRawTarget();

    final volTarget = _isLive
        ? _rawTarget
        : (_mode == SoundVisualMode.paused
            ? _rawTarget * 0.35
            : 0.08 + 0.04 * (0.5 + 0.5 * math.sin(t * _tau / 5.0)));

    // Dual envelopes — fast → shape; slow → brightness / breath.
    _frame.fast = _ar(_frame.fast, volTarget, 0.035, 0.18, dt);
    _frame.slow = _ar(_frame.slow, volTarget, 0.13, 0.42, dt);

    final intensity = _smoothstep(0.05, 0.7, _frame.fast);
    final flowSpeed = 0.06 + intensity * 0.5;
    if (!reduce && _mode != SoundVisualMode.complete) {
      _frame.flowPhase = (_frame.flowPhase + dt * flowSpeed) % 1.0;
    }

    _frame.time = t;
    _frame.breath = reduce
        ? 0.5
        : 0.5 + 0.5 * math.sin(t * _tau / (_isLive ? 3.8 : 4.5));
    _frame.mode = _mode;
    _frame.quality = _profile;
    _frame.showProgressRing = widget.showProgressRing;
    _frame.progress = widget.progress;

    final profile = _profile;
    if (!_isLive && _mode != SoundVisualMode.complete) {
      final frame = (t * profile.targetFps).floor();
      if (frame == _paintEpoch) return;
      _paintEpoch = frame;
    }

    _frame.bump();
  }

  @override
  Widget build(BuildContext context) {
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
                painter: _painter,
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
