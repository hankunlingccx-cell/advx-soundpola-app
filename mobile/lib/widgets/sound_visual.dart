import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../audio/audio_features.dart';
import '../theme/app_colors.dart';
import '../visual/audio_feature_timeline.dart';

/// 四象限严格镜像声场：右上象限多峰母体＋双向交叠线束，再水平／垂直镜像。
/// 待机即含反向弯曲、层级交换与中心桥接；声音增强交叠幅度，禁止整图 scale。
enum SoundVisualMode { idle, recording, paused, complete, playback }

const _tau = math.pi * 2;
const _halfPi = math.pi / 2;

/// Outer/mid surface streams (radial layers) + separate core streams.
const _surfaceStreamsHigh = 18;
const _surfaceStreamsMed = 14;
const _surfaceStreamsLow = 10;
const _coreStreamsHigh = 8;
const _coreStreamsMed = 6;
const _coreStreamsLow = 4;
const _particlesPerStream = 60;

const _cMint = Color(0xFF63E0CB);
const _cBlue = Color(0xFF56B8FF);
const _cViolet = Color(0xFF8875FF);
const _cPink = Color(0xFFC98AFF);

double _smoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _ar(double cur, double target, double attack, double release, double dt) {
  final rate = target > cur ? attack : release;
  final k = 1.0 - math.exp(-dt / rate.clamp(0.001, 2.0));
  return cur + (target - cur) * k;
}

double _gauss(double t, double center, double width) {
  final z = (t - center) / width;
  return math.exp(-z * z);
}

class _Drive {
  const _Drive({
    required this.fast,
    required this.slow,
    required this.bass,
    required this.lowMid,
    required this.mid,
    required this.highMid,
    required this.treble,
    required this.centroid,
    required this.flux,
    required this.onset,
    required this.zcr,
    required this.breath,
    required this.spectrum,
  });

  final double fast;
  final double slow;
  final double bass;
  final double lowMid;
  final double mid;
  final double highMid;
  final double treble;
  final double centroid;
  final double flux;
  final double onset;
  final double zcr;
  final double breath;
  final List<double> spectrum;

  /// Log-ish local spectrum sample for a stream (0–1 along stream stack).
  double localSpectrum(double streamU) {
    if (spectrum.isEmpty) {
      return (bass * (1 - streamU) + mid * 0.55 + treble * streamU)
          .clamp(0.0, 1.0);
    }
    final n = spectrum.length;
    final x = streamU.clamp(0.0, 1.0) * (n - 1);
    final i0 = x.floor().clamp(0, n - 1);
    final i1 = (i0 + 1).clamp(0, n - 1);
    final f = x - i0;
    // Soft neighborhood average avoids single-bin jitter
    final iL = (i0 - 1).clamp(0, n - 1);
    final iR = (i1 + 1).clamp(0, n - 1);
    final center = spectrum[i0] * (1 - f) + spectrum[i1] * f;
    return (0.2 * spectrum[iL] + 0.6 * center + 0.2 * spectrum[iR])
        .clamp(0.0, 1.0);
  }
}

/// Multi-peak mother contour (t ∈ [0,1]). Audio reshapes peaks/grooves,
/// not mostly base radius — keeps kaleidoscope fold from looking like breath-scale.
double _contourRadius(double t, _Drive d, {required bool core}) {
  // Overall radius ≤~20% of dynamics; structure from peaks/grooves.
  final spread = (d.fast * 0.55 + d.onset * 0.25 + d.slow * 0.20).clamp(0.0, 1.0);
  final pinch = (d.bass * 0.55 + d.lowMid * 0.25 + d.slow * 0.20).clamp(0.0, 1.0);
  final bend = (d.mid * 0.45 + d.lowMid * 0.25 + d.flux * 0.30).clamp(0.0, 1.0);
  final detail =
      (d.treble * 0.40 + d.highMid * 0.30 + d.zcr * 0.15 + d.flux * 0.15)
          .clamp(0.0, 1.0);

  // Peak centers migrate with timbre — not fixed at 0.1 / 0.5 / 0.9.
  final mainCenter = (0.50 + (bend - 0.35) * 0.22).clamp(0.30, 0.70);
  final hCenter = (0.09 + detail * 0.10 - bend * 0.05).clamp(0.03, 0.22);
  final vCenter = (0.91 - detail * 0.10 + bend * 0.05).clamp(0.78, 0.97);

  // Higher flux → narrower lobes → stronger fold silhouette.
  final mainW = 0.22 - d.flux * 0.07;
  final edgeW = 0.16 - detail * 0.045;

  final mainStrength = core
      ? 0.035 + d.slow * 0.06 + pinch * 0.055
      : 0.075 +
          d.bass * 0.13 +
          d.mid * 0.15 +
          spread * 0.06 +
          d.onset * 0.08;

  final edgeStrength = core
      ? 0.025 + detail * 0.035
      : 0.055 + detail * 0.14 + d.flux * 0.07 + spread * 0.035;

  final mainPeak = mainStrength * _gauss(t, mainCenter, mainW);
  final horizontalPeak = edgeStrength * _gauss(t, hCenter, edgeW);
  final verticalPeak = edgeStrength * _gauss(t, vCenter, edgeW);

  final grooveCenterA = (hCenter + mainCenter) * 0.5;
  final grooveCenterB = (mainCenter + vCenter) * 0.5;
  final grooveStrength =
      core ? 0.008 + pinch * 0.015 : 0.018 + pinch * 0.055 + d.flux * 0.065;
  final grooves = grooveStrength *
      (_gauss(t, grooveCenterA, 0.075) + _gauss(t, grooveCenterB, 0.075));

  // spread ≤ ~20% of radius budget
  final base = core
      ? 0.105 + d.slow * 0.025
      : 0.48 +
          spread * 0.055 +
          d.bass * 0.02 +
          d.onset * 0.035 +
          d.breath * 0.008;

  final microFold = core
      ? math.sin(t * math.pi * 4) * detail * 0.006
      : math.sin(t * math.pi * 4 + bend * 1.8) * detail * 0.018 +
          math.sin(t * math.pi * 7 - d.flux) * d.flux * 0.012;

  final radius =
      base + mainPeak + horizontalPeak + verticalPeak - grooves + microFold;

  return core ? radius.clamp(0.055, 0.30) : radius.clamp(0.30, 0.95);
}

/// Absolute layer depth + opposite-family weave + radial layer swap + center bridge.
/// Idle already has controlled cross-folds; audio amplifies them (never uniform scale).
Offset _quadrantPoint({
  required double t,
  required double layerU,
  required int streamIndex,
  required int streamCount,
  required _Drive d,
  required bool core,
  required double time,
}) {
  final streamU =
      streamCount <= 1 ? 0.5 : streamIndex / (streamCount - 1);
  final local = d.localSpectrum(streamU);

  // Layer-weighted band mix: inner→bass, mid→mid, outer→treble
  final band =
      (d.bass * (1 - streamU) * 0.55 +
              d.lowMid * (1 - streamU) * 0.25 +
              d.mid * 0.45 +
              d.highMid * streamU * 0.35 +
              d.treble * streamU * 0.40 +
              local * 0.55)
          .clamp(0.0, 1.0);

  final spread =
      (d.fast * 0.50 + d.onset * 0.25 + d.slow * 0.15 + band * 0.10)
          .clamp(0.0, 1.0);
  final bend =
      (d.mid * 0.40 + d.lowMid * 0.20 + d.flux * 0.25 + local * 0.35)
          .clamp(0.0, 1.0);
  final fold =
      (d.mid * 0.28 + d.treble * 0.18 + d.flux * 0.30 + local * 0.30)
          .clamp(0.0, 1.0);
  final detail =
      (d.treble * 0.35 + d.highMid * 0.25 + d.zcr * 0.20 + d.flux * 0.20)
          .clamp(0.0, 1.0);
  final pinch =
      (d.bass * 0.55 + d.lowMid * 0.20 + d.slow * 0.25).clamp(0.0, 1.0);
  final energy =
      (d.fast * 0.35 + d.mid * 0.25 + d.flux * 0.20 + band * 0.20)
          .clamp(0.0, 1.0);

  // Lock axes so H/V mirrors stay seamless.
  final edgeLock =
      math.pow(math.sin(math.pi * t).clamp(0.0, 1.0), 1.25).toDouble();

  // Slow idle weave (~10s drift) + audio phase; always active, louder when live.
  final idlePhase = time * 0.16;
  final phase = idlePhase +
      time * (d.flux * 0.28) +
      d.mid * 2.4 +
      d.treble * 1.3;

  final foldWaveA = math.sin(t * math.pi * 2 + phase);
  final foldWaveB = math.sin(t * math.pi * 4 - phase * 0.65);

  // Peak/valley migration along contour.
  final tOffset = edgeLock *
      (foldWaveA * (0.010 + fold * 0.065) +
          foldWaveB * (0.005 + d.flux * 0.028) +
          (bend - 0.35) * math.sin(math.pi * t) * 0.055);
  final tWarp = (t + tOffset).clamp(0.0, 1.0);
  final mother = _contourRadius(tWarp, d, core: core);

  // Shallower absolute depth — room for weave / bridge (not a thick empty ring).
  final surfaceDepth = core ? 0.048 : 0.11 + spread * 0.028;
  final layerDepth =
      surfaceDepth * math.pow(1.0 - layerU, 0.92).toDouble();

  final radialPleat = edgeLock *
      (math.sin(t * math.pi * 3 + phase) *
              (0.006 + fold * (core ? 0.018 : 0.048)) +
          math.cos(t * math.pi * 5 - phase * 0.7) *
              detail *
              (core ? 0.008 : 0.022)) *
      (0.35 + layerU * 0.65);

  final layerDirection = (layerU - 0.5) * 2.0;
  final angularFold = edgeLock *
      (foldWaveA * fold * (core ? 0.035 : 0.100) +
          foldWaveB * d.flux * (core ? 0.020 : 0.055) +
          layerDirection *
              math.cos(t * math.pi * 2 + phase) *
              (0.010 + fold * 0.045));

  // ── Opposite families: even / odd reverse bend → 1–2 mid-quadrant crosses
  final familyDirection = streamIndex.isEven ? 1.0 : -1.0;
  // Idle base 0.042–0.055; audio lifts toward ~0.10
  final crossStrength =
      (0.045 + energy * 0.040 + d.flux * 0.025 + d.onset * 0.02)
          .clamp(0.035, 0.12);
  final crossFold = edgeLock *
      familyDirection *
      math.sin(t * math.pi * 2.0 + idlePhase) *
      crossStrength;

  // Slow idle S-fold so standby is never a fixed ring.
  final idleFold = edgeLock *
      (math.sin(t * math.pi * 2.0 + idlePhase) * 0.028 +
          math.sin(t * math.pi * 4.0 - idlePhase * 0.7) * 0.012);

  var angle =
      tWarp * _halfPi + angularFold + crossFold + idleFold;

  // Flux / mid can gently reverse family lean without breaking determinism.
  angle += edgeLock *
      familyDirection *
      d.flux *
      math.sin(t * math.pi * 2.0 - idlePhase * 0.5) *
      0.035;

  // ── Layer order swap: outer dips in / inner flips out at cross zones
  final crossDepth =
      (0.035 + energy * 0.035 + d.bass * 0.015 + d.flux * 0.02)
          .clamp(0.025, 0.09);
  final layerOrder = layerU - 0.5;
  final layerCross = math.sin(t * math.pi * 2.0 + idlePhase) *
      layerOrder *
      crossDepth *
      (core ? 0.55 : 1.0);

  final onsetFold = d.onset * edgeLock * (layerU - 0.35);
  var radius = mother -
      layerDepth +
      radialPleat +
      layerCross +
      onsetFold * (core ? 0.025 : 0.085);

  radius -= pinch * (1.0 - layerU) * (core ? 0.016 : 0.042);

  // ── Center bridge: some streams tuck toward core (closes the empty gap)
  final bridgeMask = math.exp(-math.pow((t - 0.5) / 0.18, 2));
  final bridgeDepth =
      bridgeMask * (0.035 + layerU * 0.085) * (core ? 0.35 : 1.0);
  // Even family bridges deeper; odd family skims — weave into core.
  final bridgeLean = streamIndex.isEven ? 1.0 : 0.55;
  radius -= bridgeDepth * bridgeLean * (0.70 + energy * 0.30);

  if (core) {
    radius += d.slow *
        edgeLock *
        math.sin(t * math.pi * 3 + phase * 0.4) *
        0.012;
    // Core also uses opposite families for a tiny folded knot.
    radius += familyDirection *
        math.sin(t * math.pi * 2 + idlePhase) *
        0.012 *
        edgeLock;
  }

  angle = angle.clamp(0.0, _halfPi);
  // Allow surface streams closer to core so bridge is visible.
  radius = radius.clamp(core ? 0.035 : 0.12, core ? 0.36 : 1.05);

  return Offset(radius * math.cos(angle), radius * math.sin(angle));
}

class _VisualFrame extends ChangeNotifier {
  double fast = 0;
  double slow = 0.05;
  double bass = 0.12;
  double lowMid = 0.12;
  double mid = 0.15;
  double highMid = 0.1;
  double treble = 0.08;
  double centroid = 0.35;
  double flux = 0;
  double onset = 0;
  double zcr = 0.2;
  List<double> spectrum = const [];
  double time = 0;
  double breath = 0.5;
  double flowPhase = 0;
  SoundVisualMode mode = SoundVisualMode.idle;
  VisualQualityProfile quality = VisualQualityProfile.idle;
  bool showProgressRing = false;
  double progress = 0;

  void bump() => notifyListeners();
}

/// Packed quadrant draw list: x,y,r,a,cr,cg,cb
class _QuadrantBuffer {
  Float32List data = Float32List(0);
  int count = 0;

  void ensure(int n) {
    final need = n * 7;
    if (data.length < need) data = Float32List(need);
    count = n;
  }
}

class _SoundVisualPainter extends CustomPainter {
  _SoundVisualPainter(this.frame) : super(repaint: frame);

  final _VisualFrame frame;
  final _QuadrantBuffer _buf = _QuadrantBuffer();
  final Paint _paint = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = side * 0.78 * frame.quality.resolutionScale;

    final drive = _Drive(
      fast: frame.fast,
      slow: frame.slow,
      bass: frame.bass,
      lowMid: frame.lowMid,
      mid: frame.mid,
      highMid: frame.highMid,
      treble: frame.treble,
      centroid: frame.centroid,
      flux: frame.flux,
      onset: frame.onset,
      zcr: frame.zcr,
      breath: frame.breath,
      spectrum: frame.spectrum,
    );

    final (surfaceN, coreN) = switch (frame.quality.tier) {
      VisualQuality.high => (_surfaceStreamsHigh, _coreStreamsHigh),
      VisualQuality.medium => (_surfaceStreamsMed, _coreStreamsMed),
      VisualQuality.low => (_surfaceStreamsLow, _coreStreamsLow),
    };
    final particleStep = frame.quality.tier == VisualQuality.low ? 2 : 1;
    final bright = (0.78 + frame.slow * 0.18).clamp(0.68, 1.04);
    final flowPhase = frame.flowPhase;
    final time = frame.time;
    final centroid = drive.centroid;

    final ptsPer = (_particlesPerStream / particleStep).ceil();
    _buf.ensure((surfaceN + coreN) * ptsPer);

    var write = 0;

    void emitStream({
      required int streamIndex,
      required int streamCount,
      required bool core,
      required double baseAlpha,
      required double baseR,
      required Color col0,
      required Color col1,
      required double speed,
    }) {
      final layerU =
          streamCount <= 1 ? 0.5 : streamIndex / (streamCount - 1);
      final densMul = 1.0 + (streamIndex.isEven ? -0.03 : 0.025) * drive.treble;
      final sizeMul = 1.0 + drive.fast * 0.05 + (core ? 0.0 : drive.treble * 0.04);
      final n = _particlesPerStream;
      final idlePhase = time * 0.16;

      for (var p = 0; p < n; p += particleStep) {
        // Flow along angular contour; all mirrors share phase.
        final shift = flowPhase * n * speed;
        final idx = (p + shift.floor()) % n;
        final frac = shift - shift.floor();
        final t0 = (idx + 0.5) / n;
        final t1 = ((idx + 1) % n + 0.5) / n;
        var t = t0;
        if ((t1 - t0).abs() < 0.5) {
          t = _lerp(t0, t1, frac);
        } else {
          t = t0;
        }

        final pos = _quadrantPoint(
          t: t,
          layerU: layerU,
          streamIndex: streamIndex,
          streamCount: streamCount,
          d: drive,
          core: core,
          time: time,
        );

        final axisSoft =
            _smoothstep(0.0, 0.06, t) * _smoothstep(0.0, 0.06, 1.0 - t);
        final radial = math.sqrt(pos.dx * pos.dx + pos.dy * pos.dy);
        final centerFade = core
            ? (0.45 + 0.55 * _smoothstep(0.04, 0.14, radial))
            : (0.40 + 0.60 * _smoothstep(0.06, 0.18, radial));
        final layerFade = core
            ? 1.0
            : _lerp(0.58, 1.0, _smoothstep(0.12, 0.78, layerU));

        // Soften alpha near weave crossings so over/under reads as fabric, not glare.
        final crossAmt =
            math.sin(t * math.pi * 2.0 + idlePhase).abs().clamp(0.0, 1.0);
        final weaveFade = 1.0 - crossAmt * 0.18;

        // Opposite family: slight deeper teal / cool blue — no random speckles.
        final familyTint = streamIndex.isEven
            ? col1
            : Color.lerp(col1, const Color(0xFF3AB8A8), 0.22)!;

        final col = Color.lerp(col0, familyTint, t.clamp(0.0, 1.0))!;
        final alpha = (baseAlpha *
                densMul *
                bright *
                axisSoft.clamp(0.35, 1.0) *
                centerFade *
                layerFade *
                weaveFade)
            .clamp(0.05, 0.92);
        final radius =
            (baseR * sizeMul * (core ? 0.85 : _lerp(0.72, 1.0, layerU)))
                .clamp(0.38, 1.15);

        final o = write * 7;
        _buf.data[o] = pos.dx;
        _buf.data[o + 1] = pos.dy;
        _buf.data[o + 2] = radius;
        _buf.data[o + 3] = alpha;
        _buf.data[o + 4] = col.r;
        _buf.data[o + 5] = col.g;
        _buf.data[o + 6] = col.b;
        write++;
      }
    }

    // ── Surface film (outer multi-peak contour layers) ──────────────
    final violetMix = _smoothstep(0.35, 0.85, drive.fast) *
        _smoothstep(0.4, 0.9, centroid) *
        0.5;
    final outerCol0 = _cMint;
    final outerCol1 = Color.lerp(
      Color.lerp(_cMint, _cBlue, 0.25 + centroid * 0.25)!,
      _cViolet,
      violetMix,
    )!;
    final pink = _smoothstep(0.55, 0.95, centroid) * drive.treble * 0.3;
    final midCol1 = Color.lerp(outerCol1, _cPink, pink)!;

    for (var i = 0; i < surfaceN; i++) {
      final u = surfaceN <= 1 ? 0.5 : i / (surfaceN - 1);
      // Mid layers clearest; outer faintest; inner quieter.
      final alpha = u < 0.25
          ? 0.42
          : (u < 0.7 ? _lerp(0.78, 0.92, (u - 0.25) / 0.45) : _lerp(0.55, 0.28, (u - 0.7) / 0.3));
      final pr = u < 0.3 ? 0.55 : (u < 0.75 ? 0.82 : 0.48);
      emitStream(
        streamIndex: i,
        streamCount: surfaceN,
        core: false,
        baseAlpha: alpha,
        baseR: pr,
        col0: outerCol0,
        col1: u > 0.65 ? midCol1 : Color.lerp(outerCol0, outerCol1, 0.35 + u * 0.4)!,
        speed: 0.85 + u * 0.25,
      );
    }

    // ── Folded core (same multi-peak topology, slower / smaller) ─────
    if (frame.quality.tier != VisualQuality.low || coreN > 0) {
      final coreCol = Color.lerp(_cMint, _cBlue, 0.08 + drive.slow * 0.1)!;
      for (var i = 0; i < coreN; i++) {
        emitStream(
          streamIndex: i,
          streamCount: coreN,
          core: true,
          baseAlpha: 0.55 - i * 0.04,
          baseR: 0.52,
          col0: _cMint,
          col1: coreCol,
          speed: 0.55,
        );
      }
    }

    _buf.count = write;

    // Draw once; mirror with scale (±1, ±1) — no per-quadrant regeneration.
    canvas.save();
    canvas.translate(cx, cy);

    for (final sx in const [1.0, -1.0]) {
      for (final sy in const [1.0, -1.0]) {
        canvas.save();
        canvas.scale(sx, sy);
        // Tiny alpha variance by quadrant without moving particles.
        final aMul = 1.0 - ((sx < 0 ? 1 : 0) + (sy < 0 ? 1 : 0)) * 0.02;
        for (var i = 0; i < _buf.count; i++) {
          final o = i * 7;
          _paint.color = Color.from(
            alpha: (_buf.data[o + 3] * aMul).clamp(0.0, 1.0),
            red: _buf.data[o + 4],
            green: _buf.data[o + 5],
            blue: _buf.data[o + 6],
          );
          canvas.drawCircle(
            Offset(_buf.data[o] * scale, _buf.data[o + 1] * scale),
            _buf.data[o + 2],
            _paint,
          );
        }
        canvas.restore();
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

  double _bassT = 0.12,
      _lowMidT = 0.12,
      _midT = 0.15,
      _highMidT = 0.1,
      _trebleT = 0.08;
  double _centroidT = 0.35, _fluxT = 0, _onsetT = 0, _zcrT = 0.2;
  double _fastT = 0.04, _slowT = 0.06;
  List<double> _spectrumT = const [];

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
    _syncTargets();
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

  void _onFeatures() => _syncTargets();
  void _onLiveVolume() => _syncTargets();

  void _syncTargets() {
    final f = widget.features?.value;
    final live = widget.liveVolume?.value;

    if (_isLive && f != null) {
      // Prefer analyzer AGC envelopes — avoid double perceptual compression.
      _fastT = f.fastEnvelope > 0.001
          ? f.fastEnvelope
          : (f.gatedRms > 0.001
              ? f.gatedRms
              : (live ?? f.rms).clamp(0.0, 1.0));
      _slowT = f.slowEnvelope > 0.001 ? f.slowEnvelope : _fastT * 0.85;
      _bassT = f.bass;
      _lowMidT = f.lowMid;
      _midT = f.mid;
      _highMidT = f.highMid;
      _trebleT = f.treble;
      _centroidT = f.spectralCentroid;
      _fluxT = f.spectralFlux;
      _onsetT = f.onset > 0.22 ? f.onset : 0.0;
      _zcrT = f.zeroCrossingRate;
      _spectrumT = f.spectrum;
      _rawTarget = _fastT;
      return;
    }

    final rawVolume =
        live ?? f?.gatedRms ?? f?.rms ?? widget.amplitude;
    _rawTarget = rawVolume.clamp(0.0, 1.0);

    // Idle / non-live: soft deterministic drive (never fully flat).
    final t = _frame.time;
    final idlePhase = t * 0.16;
    final v = _mode == SoundVisualMode.paused
        ? _rawTarget * 0.35
        : (0.03 + 0.025 * (0.5 + 0.5 * math.sin(idlePhase)));
    _fastT = v;
    _slowT = 0.05 + 0.03 * (0.5 + 0.5 * math.sin(idlePhase * 0.7));
    _bassT = 0.10 + 0.06 * (0.5 + 0.5 * math.sin(idlePhase * 0.5));
    _lowMidT = 0.10 + 0.05 * (0.5 + 0.5 * math.cos(idlePhase * 0.6));
    _midT = 0.12 + 0.08 * (0.5 + 0.5 * math.sin(idlePhase + 1.2));
    _highMidT = 0.06;
    _trebleT = 0.04;
    _centroidT = 0.32;
    _fluxT = 0.04 + 0.03 * (0.5 + 0.5 * math.sin(idlePhase * 1.3));
    _onsetT = 0;
    _zcrT = 0.15;
    _spectrumT = const [];
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
    _syncTargets();

    // Analyzer already applied AR; light UI smoothing only for continuity.
    _frame.fast = _ar(_frame.fast, _fastT, 0.016, 0.10, dt);
    _frame.slow = _ar(_frame.slow, _slowT, 0.08, 0.32, dt);
    _frame.bass = _ar(_frame.bass, _bassT, 0.030, 0.18, dt);
    _frame.lowMid = _ar(_frame.lowMid, _lowMidT, 0.028, 0.14, dt);
    _frame.mid = _ar(_frame.mid, _midT, 0.022, 0.11, dt);
    _frame.highMid = _ar(_frame.highMid, _highMidT, 0.020, 0.10, dt);
    _frame.treble = _ar(_frame.treble, _trebleT, 0.018, 0.09, dt);
    _frame.centroid = _ar(_frame.centroid, _centroidT, 0.08, 0.28, dt);
    _frame.flux = _ar(_frame.flux, _fluxT, 0.015, 0.12, dt);
    _frame.onset = _ar(_frame.onset, _onsetT, 0.006, 0.22, dt);
    _frame.zcr = _ar(_frame.zcr, _zcrT, 0.04, 0.14, dt);
    if (_spectrumT.isNotEmpty) _frame.spectrum = _spectrumT;

    final intensity = _smoothstep(0.05, 0.7, _frame.fast);
    final flowSpeed = 0.045 * (1.0 + intensity * 0.8);
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
          (true, true) => math.min(maxW * 0.98, maxH * 0.98),
          (true, false) => maxW * 0.98,
          (false, true) => maxH * 0.92,
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

/// Deterministic offscreen renderer for Indexed-MJPEG bake.
/// Walks [AudioFeatureTimeline] with the same AR / flow rules as live canvas.
class SoundVisualOffscreen {
  SoundVisualOffscreen({
    required this.seed,
    this.quality = VisualQuality.medium,
  }) : _painter = _SoundVisualPainter(_frame);

  final int seed;
  final VisualQuality quality;
  final _VisualFrame _frame = _VisualFrame();
  final _SoundVisualPainter _painter;

  double _fast = 0.04,
      _slow = 0.06,
      _bass = 0.12,
      _lowMid = 0.12,
      _mid = 0.15,
      _highMid = 0.1,
      _treble = 0.08,
      _centroid = 0.35,
      _flux = 0,
      _onset = 0,
      _zcr = 0.2;
  double _flowPhase = 0;
  List<double> _spectrum = const [];

  void _applyTargets(AudioFeatures f, double timeSec, double dt) {
    final fastT = f.fastEnvelope > 0.001 ? f.fastEnvelope : f.gatedRms;
    final slowT = f.slowEnvelope > 0.001 ? f.slowEnvelope : fastT * 0.85;
    _fast = _ar(_fast, fastT, 0.016, 0.10, dt);
    _slow = _ar(_slow, slowT, 0.08, 0.32, dt);
    _bass = _ar(_bass, f.bass, 0.030, 0.18, dt);
    _lowMid = _ar(_lowMid, f.lowMid, 0.028, 0.14, dt);
    _mid = _ar(_mid, f.mid, 0.022, 0.11, dt);
    _highMid = _ar(_highMid, f.highMid, 0.020, 0.10, dt);
    _treble = _ar(_treble, f.treble, 0.018, 0.09, dt);
    _centroid = _ar(_centroid, f.spectralCentroid, 0.08, 0.28, dt);
    _flux = _ar(_flux, f.spectralFlux, 0.015, 0.12, dt);
    final onsetT = f.onset > 0.22 ? f.onset : 0.0;
    _onset = _ar(_onset, onsetT, 0.006, 0.22, dt);
    _zcr = _ar(_zcr, f.zeroCrossingRate, 0.04, 0.14, dt);
    if (f.spectrum.isNotEmpty) _spectrum = f.spectrum;

    final intensity = _smoothstep(0.05, 0.7, _fast);
    final flowSpeed = 0.045 * (1.0 + intensity * 0.8);
    _flowPhase = (_flowPhase + dt * flowSpeed) % 1.0;

    _frame.fast = _fast;
    _frame.slow = _slow;
    _frame.bass = _bass;
    _frame.lowMid = _lowMid;
    _frame.mid = _mid;
    _frame.highMid = _highMid;
    _frame.treble = _treble;
    _frame.centroid = _centroid;
    _frame.flux = _flux;
    _frame.onset = _onset;
    _frame.zcr = _zcr;
    _frame.spectrum = _spectrum;
    _frame.time = timeSec;
    _frame.flowPhase = _flowPhase;
    _frame.breath = 0.5 + 0.5 * math.sin(timeSec * _tau / 3.8);
    _frame.mode = SoundVisualMode.recording;
    _frame.quality = VisualQualityProfile.forTier(quality);
    _frame.showProgressRing = false;
    _frame.progress = 0;
  }

  /// Advance state to [timeMs] using timeline sample (call in time order).
  void seek(AudioFeatureTimeline timeline, int timeMs, {required double dt}) {
    final f = timeline.sampleAt(timeMs);
    _applyTargets(f, timeMs / 1000.0, dt);
  }

  Future<ui.Image> renderImage(int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(width.toDouble(), height.toDouble());
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF020404),
    );
    _painter.paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    return image;
  }

  /// Warm-up AR state from t=0 to first frame without emitting images.
  void warmUp(AudioFeatureTimeline timeline, int untilMs, double stepMs) {
    var t = 0;
    final dt = stepMs / 1000.0;
    while (t < untilMs) {
      seek(timeline, t, dt: dt);
      t += stepMs.round();
    }
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
