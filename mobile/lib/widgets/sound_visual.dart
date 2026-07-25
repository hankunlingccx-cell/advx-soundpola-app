import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../audio/audio_features.dart';
import '../theme/app_colors.dart';
import 'visual_shape.dart';

/// Organic ribbon kaleidoscope: analyze @25–30 Hz, render @60 with lerp.
/// One Seed petal geometry → Canvas rotate ×6 (never six independent datasets).
enum SoundVisualMode { idle, recording, paused, complete, playback }

const _tau = math.pi * 2;
const _sectorCount = 6;
const _bundleCount = 3;
const _strandCount = 4;
const _controlPoints = 24;
const _particleSlots = 8; // fixed slots; quality caps how many draw

const _cMint = Color(0xFF63E0CB);
const _cBass = Color(0xFF4FA9E8);
const _cMid = Color(0xFF7667E8);
const _cHi = Color(0xFFD9FFF8);
const _cOnset = Color(0xFFD879C8);

double _hash01(double n) {
  final x = math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - x.floorToDouble();
}

double _smoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

class _BundleSpec {
  const _BundleSpec({
    required this.id,
    required this.rStart,
    required this.rEnd,
    required this.thHome,
    required this.sweep,
    required this.foldSign,
  });

  final double id;
  final double rStart;
  final double rEnd;
  final double thHome;
  final double sweep;
  final double foldSign;
}

List<_BundleSpec> _fixedBundles(int seed) {
  return List.generate(_bundleCount, (i) {
    double h(double k) => _hash01(seed * 0.031 + i * 19.7 + k * 7.1);
    return _BundleSpec(
      id: i + seed * 0.001,
      rStart: 0.10 + 0.12 * h(1),
      rEnd: 0.58 + 0.34 * h(2),
      thHome: (0.12 + 0.76 * ((i + 0.5) / _bundleCount * 0.55 + h(3) * 0.45))
          .clamp(0.08, 0.92),
      sweep: (0.22 + 0.38 * h(4)) * (h(5) < 0.5 ? -1.0 : 1.0),
      foldSign: h(6) < 0.5 ? -1.0 : 1.0,
    );
  });
}

/// Polar control point for one spine sample (r, thLocal in half-sector).
Offset _spineAt({
  required double u,
  required _BundleSpec b,
  required double time,
  required double breath,
  required double awake,
  required double curvatureScale,
  required AudioFeatures f,
  required bool shapeLive,
}) {
  final tipSharp = shapeLive
      ? (0.25 + f.pitch * 0.7 + f.treble * 0.2).clamp(0.2, 0.95)
      : 0.4;
  final bendFreq =
      shapeLive ? (1.1 + f.pitch * 2.4 + f.mid * 1.2) : (1.2 + f.pitch * 0.35);
  final bendAmp = (0.045 + f.mid * 0.11 + f.pitch * 0.06) * curvatureScale;
  final fold =
      (0.03 + f.pitch * 0.08 + f.mid * 0.05) * curvatureScale * b.foldSign;
  final wideBass = f.bass * 0.07 * awake * curvatureScale;

  final uEase = math.pow(u.clamp(0.0, 1.0), 0.82 + tipSharp * 0.45).toDouble();
  var r = b.rStart + (b.rEnd - b.rStart) * uEase;
  r += wideBass * uEase;
  r -= f.treble * 0.04 * tipSharp * uEase;
  r += bendAmp *
      0.55 *
      math.sin(u * _tau * bendFreq * 0.55 + b.id + time * 0.11) *
      (0.35 + f.mid);
  r += bendAmp *
      0.25 *
      math.sin(u * _tau * bendFreq * 1.1 - time * 0.09 + b.id * 2) *
      f.mid;

  var th = b.thHome + b.sweep * (u - 0.5) * (0.55 + f.pitch * 0.35);
  th += bendAmp *
      1.15 *
      math.sin(u * math.pi * bendFreq + time * 0.13 + b.id) *
      (0.4 + f.mid * 0.8);
  th += fold * math.sin(u * _tau * 0.85 + time * 0.07);
  final tip = _smoothstep(0.72, 1.0, u);
  th += b.foldSign * tip * (0.06 + tipSharp * 0.08) * curvatureScale;
  r *= 1.0 - tip * tipSharp * 0.08;

  if (f.onset > 0.05 && shapeLive) {
    final pulse =
        math.exp(-math.pow((u - (time * 0.35 % 1.0)) * 6, 2).toDouble());
    r += f.onset * 0.035 * pulse;
    th += f.onset * 0.02 * pulse * b.foldSign;
  }

  r *= 1.0 + (f.rms - 0.2).clamp(-0.5, 0.8) * 0.04 * awake;
  r += breath * 0.008 * math.sin(u * math.pi + b.id);

  final voidFloor = 0.08 + 0.02 * _hash01(b.id * 3.1);
  if (u < 0.08) r = math.max(r, voidFloor + u * 0.04);
  return Offset(r.clamp(voidFloor * 0.92, 1.05), th.clamp(0.04, 0.96));
}

/// Cloud-skeleton modulation: apply only the layers that don't distort the
/// cloud-encoded curvature (rms radial scale, breath nudge, onset pulse,
/// voidFloor). Skips the bend/fold oscillations from [_spineAt] since the
/// cloud already provides the static shape.
Offset _spineAtCloud({
  required Offset base,
  required double u,
  required double bId,
  required double time,
  required double breath,
  required double awake,
  required AudioFeatures f,
  required bool shapeLive,
}) {
  var r = base.dx;
  var th = base.dy;
  // rms radial scale (mirrors _spineAt line 119)
  r *= 1.0 + (f.rms - 0.2).clamp(-0.5, 0.8) * 0.04 * awake;
  // breath radial nudge (mirrors _spineAt line 120)
  r += breath * 0.008 * math.sin(u * math.pi + bId);
  // onset pulse (mirrors _spineAt lines 112-117; foldSign not available
  // from cloud, use +1)
  if (f.onset > 0.05 && shapeLive) {
    final pulse =
        math.exp(-math.pow((u - (time * 0.35 % 1.0)) * 6, 2).toDouble());
    r += f.onset * 0.035 * pulse;
    th += f.onset * 0.02 * pulse;
  }
  final voidFloor = 0.08 + 0.02 * _hash01(bId * 3.1);
  if (u < 0.08) r = math.max(r, voidFloor + u * 0.04);
  return Offset(r.clamp(voidFloor * 0.92, 1.05), th.clamp(0.04, 0.96));
}

Offset _polarToLocal(Offset polar, double mirrorSign) {
  final sectorHalf = (_tau / _sectorCount) * 0.5;
  final theta = mirrorSign * (polar.dy * sectorHalf);
  return Offset(math.cos(theta) * polar.dx, math.sin(theta) * polar.dx);
}

Color _colorAlong({
  required double u,
  required SoundVisualMode mode,
  required AudioFeatures f,
  required double awake,
  required bool primary,
}) {
  if (mode == SoundVisualMode.idle ||
      mode == SoundVisualMode.paused ||
      mode == SoundVisualMode.complete) {
    return Color.lerp(_cMint, _cBass, 0.12 + 0.06 * math.sin(u * 2))!;
  }
  final bassW = f.bass * (1.0 - u) * 0.85;
  final midW = f.mid * math.sin(u * math.pi).clamp(0.0, 1.0);
  final hiW = f.treble * _smoothstep(0.55, 1.0, u);
  final onsetW =
      f.onset * math.exp(-math.pow((u - 0.35) * 4, 2).toDouble());
  var c = _cMint;
  c = Color.lerp(c, _cBass, (bassW * 0.75).clamp(0.0, 0.7))!;
  c = Color.lerp(c, _cMid, (midW * 0.65 * awake).clamp(0.0, 0.7))!;
  c = Color.lerp(c, _cHi, (hiW * (primary ? 0.85 : 0.45)).clamp(0.0, 0.9))!;
  c = Color.lerp(c, _cOnset, (onsetW * 0.55).clamp(0.0, 0.6))!;
  return c;
}

/// Flat buffer: bundle * controlPoints of polar Offsets (one Seed).
class _CtrlBuffer {
  _CtrlBuffer()
      : pts = List<Offset>.filled(_bundleCount * _controlPoints, Offset.zero);

  final List<Offset> pts;

  Offset get(int bundle, int i) => pts[bundle * _controlPoints + i];

  void set(int bundle, int i, Offset o) => pts[bundle * _controlPoints + i] = o;

  void copyFrom(_CtrlBuffer o) {
    for (var i = 0; i < pts.length; i++) {
      pts[i] = o.pts[i];
    }
  }

  void lerpFrom(_CtrlBuffer a, _CtrlBuffer b, double t) {
    for (var i = 0; i < pts.length; i++) {
      pts[i] = Offset.lerp(a.pts[i], b.pts[i], t)!;
    }
  }
}

void _fillTargets({
  required _CtrlBuffer out,
  required List<_BundleSpec> bundles,
  required SoundVisualShape? shape,
  required double time,
  required double breath,
  required double awake,
  required double curvatureScale,
  required AudioFeatures f,
  required bool shapeLive,
}) {
  for (var b = 0; b < _bundleCount; b++) {
    for (var i = 0; i < _controlPoints; i++) {
      final u = i / (_controlPoints - 1);
      out.set(
        b,
        i,
        shape != null
            ? _spineAtCloud(
                base: shape.bundles[b][i],
                u: u,
                bId: b + 0.001,
                time: time,
                breath: breath,
                awake: awake,
                f: f,
                shapeLive: shapeLive,
              )
            : _spineAt(
                u: u,
                b: bundles[b],
                time: time,
                breath: breath,
                awake: awake,
                curvatureScale: curvatureScale,
                f: f,
                shapeLive: shapeLive,
              ),
      );
    }
  }
}

class _SoundVisualPainter extends CustomPainter {
  _SoundVisualPainter({
    required this.ctrl,
    required this.bundles,
    required this.mode,
    required this.features,
    required this.time,
    required this.breath,
    required this.awake,
    required this.globalPhase,
    required this.quality,
    this.showProgressRing = false,
    this.progress = 0,
  });

  final _CtrlBuffer ctrl;
  final List<_BundleSpec> bundles;
  final SoundVisualMode mode;
  final AudioFeatures features;
  final double time;
  final double breath;
  final double awake;
  final double globalPhase;
  final VisualQualityProfile quality;
  final bool showProgressRing;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = side * 0.46 * (0.99 + 0.02 * breath) * quality.resolutionScale;

    final idle = mode == SoundVisualMode.idle;
    final recording =
        mode == SoundVisualMode.recording || mode == SoundVisualMode.playback;
    final brightIdle = 1.0 + 0.10 * (breath - 0.5) * 2;
    final brightRec = 0.75 + features.rms * 0.35 + features.onset * 0.08;
    final bright = (idle ? brightIdle : brightRec).clamp(0.55, 1.15);

    // Build ONE seed petal (both mirrors) in local unit space, then rotate ×6.
    final petalOps = <_StrokeSeg>[];

    for (var b = 0; b < _bundleCount; b++) {
      for (var s = 0; s < _strandCount; s++) {
        final strandOffset = s - (_strandCount - 1) * 0.5;
        final primary = strandOffset.abs() < 0.35;
        final baseAlpha = idle
            ? (primary ? 0.52 : 0.28)
            : recording
                ? (primary ? 0.78 : 0.42)
                : (primary ? 0.55 : 0.3);
        final strokeW = primary ? 1.15 : 0.75;

        for (final mirror in [1.0, -1.0]) {
          final cart = List<Offset>.generate(_controlPoints, (i) {
            final pol = ctrl.get(b, i);
            final p = _polarToLocal(pol, mirror);
            // Parallel strand via finite difference normal in local space
            return p;
          });
          for (var i = 0; i < _controlPoints - 1; i++) {
            final uMid = (i + 0.5) / (_controlPoints - 1);
            final p0 = cart[i];
            final p1 = cart[i + 1];
            final tx = p1.dx - p0.dx;
            final ty = p1.dy - p0.dy;
            final len = math.sqrt(tx * tx + ty * ty) + 1e-5;
            final nx = -ty / len;
            final ny = tx / len;
            final spacing = 0.014 + ctrl.get(b, i).dx * 0.006;
            final o0 = Offset(
              p0.dx + nx * strandOffset * spacing,
              p0.dy + ny * strandOffset * spacing,
            );
            final o1 = Offset(
              p1.dx + nx * strandOffset * spacing,
              p1.dy + ny * strandOffset * spacing,
            );
            final tipFade = 1.0 - _smoothstep(0.82, 1.0, uMid) * 0.55;
            var alpha =
                (baseAlpha * bright * tipFade * (0.85 + 0.15 * awake))
                    .clamp(0.08, 0.95);
            if (recording &&
                primary &&
                features.treble > 0.35 &&
                uMid > 0.6) {
              alpha = (alpha + features.treble * 0.2).clamp(0.0, 1.0);
            }
            final color = _colorAlong(
              u: uMid,
              mode: mode,
              f: features,
              awake: awake,
              primary: primary,
            );
            petalOps.add(
              _StrokeSeg(
                o0: o0,
                o1: o1,
                color: color,
                alpha: alpha,
                width: strokeW,
                bloom: quality.bloom &&
                    recording &&
                    primary &&
                    alpha > 0.72 &&
                    features.treble + features.onset > 0.4,
              ),
            );
          }
        }
      }
    }

    // Fixed particle slots (u positions); only first N drawn.
    final particleN = quality.particleCount.clamp(0, _particleSlots);

    void drawPetal(Canvas c) {
      for (final seg in petalOps) {
        if (seg.bloom) {
          c.drawLine(
            Offset(seg.o0.dx * scale, seg.o0.dy * scale),
            Offset(seg.o1.dx * scale, seg.o1.dy * scale),
            Paint()
              ..color = seg.color.withValues(alpha: 0.08)
              ..strokeWidth = seg.width + 2.2
              ..strokeCap = StrokeCap.round
              ..style = PaintingStyle.stroke,
          );
        }
        c.drawLine(
          Offset(seg.o0.dx * scale, seg.o0.dy * scale),
          Offset(seg.o1.dx * scale, seg.o1.dy * scale),
          Paint()
            ..color = seg.color.withValues(alpha: seg.alpha)
            ..strokeWidth = seg.width
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
      }
      for (var i = 0; i < particleN; i++) {
        final b = i % _bundleCount;
        final u = (0.15 + i * 0.11 + time * (0.04 + features.rms * 0.03)) % 1.0;
        final idx = (u * (_controlPoints - 1)).floor().clamp(0, _controlPoints - 2);
        final frac = (u * (_controlPoints - 1)) - idx;
        final pol = Offset.lerp(ctrl.get(b, idx), ctrl.get(b, idx + 1), frac)!;
        final mirror = i.isEven ? 1.0 : -1.0;
        final p = _polarToLocal(pol, mirror);
        final a = idle ? 0.2 : (0.18 + features.rms * 0.12);
        c.drawCircle(
          Offset(p.dx * scale, p.dy * scale),
          1.2,
          Paint()..color = _cHi.withValues(alpha: a * bright),
        );
      }
    }

    // Six rotations of the same petal — no duplicate geometry generation.
    for (var rot = 0; rot < _sectorCount; rot++) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(rot * (_tau / _sectorCount) + globalPhase);
      drawPetal(canvas);
      canvas.restore();
    }

    if (showProgressRing) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: side * 0.46 * 0.96),
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
      old.awake != awake ||
      old.globalPhase != globalPhase ||
      old.mode != mode ||
      old.quality.tier != quality.tier ||
      old.features.rms != features.rms ||
      old.features.pitch != features.pitch ||
      old.features.onset != features.onset ||
      old.progress != progress ||
      !identical(old.ctrl, ctrl);
}

class _StrokeSeg {
  _StrokeSeg({
    required this.o0,
    required this.o1,
    required this.color,
    required this.alpha,
    required this.width,
    required this.bloom,
  });

  final Offset o0;
  final Offset o1;
  final Color color;
  final double alpha;
  final double width;
  final bool bloom;
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
    this.shape,
  });

  final int seed;
  final bool active;
  final bool dark;
  final SoundVisualMode? mode;
  /// Legacy fallback when [features] is null (idle / static pages).
  final double amplitude;
  /// Prefer feeding isolate-produced features; avoids page-wide setState.
  final ValueListenable<AudioFeatures>? features;
  final bool showProgressRing;
  final double progress;
  /// Cloud-produced polar skeleton (3 bundles × 24 points). When non-null,
  /// overrides seed-based [_spineAt]; local breath/AudioFeatures modulation
  /// still applies via [_spineAtCloud]. Null = seed fallback.
  final SoundVisualShape? shape;

  @override
  State<SoundVisualCanvas> createState() => _SoundVisualCanvasState();
}

class _SoundVisualCanvasState extends State<SoundVisualCanvas>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final List<_BundleSpec> _bundles;
  final _ctrlFrom = _CtrlBuffer();
  final _ctrlTo = _CtrlBuffer();
  final _ctrlNow = _CtrlBuffer();

  final _start = DateTime.now();
  Duration _lastElapsed = Duration.zero;
  double _globalPhase = 0;
  double _awake = 0;
  double _lerpT = 1;
  double _targetInterval = 1 / 25;
  double _sinceTarget = 0;
  AudioFeatures _featFrom = AudioFeatures.silent;
  AudioFeatures _featTo = AudioFeatures.silent;
  AudioFeatures _featNow = AudioFeatures.silent;
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
    _bundles = _fixedBundles(widget.seed);
    _awake = _isLive ? 1.0 : 0.0;
    _featTo = widget.features?.value ??
        AudioFeatures(rms: widget.amplitude.clamp(0.05, 1.0));
    _featFrom = _featTo;
    _featNow = _featTo;
    _retarget(0, breath: 0.5);
    _ctrlFrom.copyFrom(_ctrlTo);
    _ctrlNow.copyFrom(_ctrlTo);
    widget.features?.addListener(_onFeatures);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant SoundVisualCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.features != widget.features) {
      oldWidget.features?.removeListener(_onFeatures);
      widget.features?.addListener(_onFeatures);
    }
    if (oldWidget.seed != widget.seed) {
      _bundles = _fixedBundles(widget.seed);
    }
    if (oldWidget.seed != widget.seed || oldWidget.shape != widget.shape) {
      final t = _lastElapsed == Duration.zero
          ? 0.0
          : _lastElapsed.inMilliseconds / 1000.0;
      _retarget(t, breath: 0.5);
      if (!_ticker.isActive) _ticker.start();
    }
    if (_isLive && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    widget.features?.removeListener(_onFeatures);
    _ticker.dispose();
    super.dispose();
  }

  void _onFeatures() {
    // Features arrive ~25–30 Hz from isolate; only mark new targets.
    // Actual control-point retarget happens on ticker at same cadence.
  }

  void _retarget(double time, {required double breath}) {
    final live = _isLive;
    final curvature = live
        ? (0.85 + 0.15 * _awake)
        : (_mode == SoundVisualMode.paused
            ? 0.15
            : (0.08 + 0.04 * breath));
    _ctrlFrom.copyFrom(_ctrlNow);
    _featFrom = _featNow;
    _featTo = widget.features?.value ??
        (_isLive
            ? AudioFeatures(rms: widget.amplitude.clamp(0.05, 1.0))
            : AudioFeatures.silent);
    _fillTargets(
      out: _ctrlTo,
      bundles: _bundles,
      shape: widget.shape,
      time: time,
      breath: breath,
      awake: _awake,
      curvatureScale: curvature,
      f: _featTo,
      shapeLive: live,
    );
    _lerpT = 0;
  }

  void _adaptQuality(double dt) {
    if (!_isLive) {
      _tier = VisualQuality.medium;
      return;
    }
    _frameTimes.add(dt);
    if (_frameTimes.length > 30) _frameTimes.removeAt(0);
    if (_frameTimes.length < 12) return;
    final avg =
        _frameTimes.reduce((a, b) => a + b) / _frameTimes.length;
    // Drop frame budget: prefer bloom off → fewer particles → lower res → fps
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
        ? 8.0 + widget.seed % 5
        : elapsed.inMilliseconds / 1000.0;
    final dt = _lastElapsed == Duration.zero
        ? 1 / 60
        : ((elapsed - _lastElapsed).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastElapsed = elapsed;

    final profile = _profile;
    // Idle 20–30 FPS: skip paints when under budget.
    final minDt = 1.0 / profile.targetFps;
    if (dt < minDt * 0.85 && _mode != SoundVisualMode.complete) {
      // Still advance soft state lightly but throttle paint via early return
      // using accumulator — simpler: only mark needsPaint every minDt.
    }

    _adaptQuality(dt);
    final breath =
        reduce ? 0.5 : 0.5 + 0.5 * math.sin(t * _tau / 7.0);
    final wakeTarget = _isLive ? 1.0 : (_mode == SoundVisualMode.paused ? 0.35 : 0.0);
    _awake += ((wakeTarget - _awake) * (dt / 0.75)).clamp(-1.0, 1.0);
    _awake = _awake.clamp(0.0, 1.0);

    // Target control points @ 20–30 Hz
    _targetInterval = _isLive ? 1 / 25 : 1 / 22;
    _sinceTarget += dt;
    if (_sinceTarget >= _targetInterval || _lerpT >= 1) {
      if (_sinceTarget >= _targetInterval) {
        _sinceTarget = 0;
        if (!reduce && _mode != SoundVisualMode.complete) {
          _retarget(t, breath: breath);
        }
      }
    }

    // High-frequency interpolation toward targets
    final lerpSpeed = _isLive ? 28.0 : 18.0;
    _lerpT = (_lerpT + dt * lerpSpeed).clamp(0.0, 1.0);
    final s = _lerpT * _lerpT * (3 - 2 * _lerpT);
    _ctrlNow.lerpFrom(_ctrlFrom, _ctrlTo, s);
    _featNow = _featFrom.lerp(_featTo, s);

    if (!reduce &&
        _mode != SoundVisualMode.paused &&
        _mode != SoundVisualMode.complete) {
      _globalPhase += 0.012 * dt * (0.4 + 0.6 * _awake);
    }

    // Throttle idle repaints to ~24 FPS
    if (!_isLive && _mode != SoundVisualMode.complete) {
      final frame = (t * profile.targetFps).floor();
      if (frame == _paintEpoch) return;
      _paintEpoch = frame;
    }

    // Complete mode is a static still: once the shape has settled, paint the
    // final frame and stop the ticker entirely, so a grid of cards does zero
    // per-frame work (the 60fps repaints were overloading the GPU and causing
    // badge ghosting). didUpdateWidget restarts the ticker on shape change.
    if (_mode == SoundVisualMode.complete && _lerpT >= 1.0) {
      if (mounted) setState(() {});
      _ticker.stop();
      return;
    }

    // Repaint only this boundary — parent page is not rebuilt.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        final side = switch ((maxW.isFinite, maxH.isFinite)) {
          (true, true) => math.min(maxW, maxH),
          (true, false) => maxW,
          (false, true) => maxH,
          _ => 240.0,
        };
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _SoundVisualPainter(
                  ctrl: _ctrlNow,
                  bundles: _bundles,
                  mode: reduce ? SoundVisualMode.complete : _mode,
                  features: _featNow,
                  time: DateTime.now().difference(_start).inMilliseconds /
                      1000.0,
                  breath: reduce
                      ? 0.5
                      : 0.5 +
                          0.5 *
                              math.sin(
                                DateTime.now()
                                        .difference(_start)
                                        .inMilliseconds /
                                    1000.0 *
                                    _tau /
                                    7.0,
                              ),
                  awake: _awake,
                  globalPhase: _globalPhase,
                  quality: _profile,
                  showProgressRing: widget.showProgressRing,
                  progress: widget.progress,
                ),
                size: Size.square(side),
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
