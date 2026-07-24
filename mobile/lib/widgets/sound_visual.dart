import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Ported from visuallization/particle-field (Axis Field V1.4 linear kaleidoscope).
enum SoundVisualMode { idle, recording, paused, complete, playback }

const _tau = math.pi * 2;

double _hash01(double n) {
  final x = math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - x.floorToDouble();
}

double _smoothNoise3(double x, double y, double z) {
  final ix = x.floorToDouble();
  final iy = y.floorToDouble();
  final iz = z.floorToDouble();
  var fx = x - ix;
  var fy = y - iy;
  var fz = z - iz;
  fx = fx * fx * (3 - 2 * fx);
  fy = fy * fy * (3 - 2 * fy);
  fz = fz * fz * (3 - 2 * fz);

  double hh(double a, double b, double c) {
    final n = math.sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453;
    return n - n.floorToDouble();
  }

  final n000 = hh(ix, iy, iz);
  final n100 = hh(ix + 1, iy, iz);
  final n010 = hh(ix, iy + 1, iz);
  final n110 = hh(ix + 1, iy + 1, iz);
  final n001 = hh(ix, iy, iz + 1);
  final n101 = hh(ix + 1, iy, iz + 1);
  final n011 = hh(ix, iy + 1, iz + 1);
  final n111 = hh(ix + 1, iy + 1, iz + 1);

  final nx00 = n000 + (n100 - n000) * fx;
  final nx10 = n010 + (n110 - n010) * fx;
  final nx01 = n001 + (n101 - n001) * fx;
  final nx11 = n011 + (n111 - n011) * fx;
  final nxy0 = nx00 + (nx10 - nx00) * fy;
  final nxy1 = nx01 + (nx11 - nx01) * fy;
  return nxy0 + (nxy1 - nxy0) * fz;
}

class _Morph {
  double globalPhase = 0;
  final layerPhase = <double>[0, 0.7, 1.4, 2.1];
  double foldAmount = 0.45;
  double lobeDepth = 0.14;
  double outerReach = 0.82;
  double flowSpeed = 0.18;
  double topologyMix = 0.48;
  double waveOrderA = 3;
  double waveOrderB = 5;
  final layerWeight = <double>[0.55, 0.75, 1.0, 1.05];

  double _foldT = 0.45;
  double _lobeT = 0.14;
  double _outerT = 0.82;
  double _flowT = 0.18;
  double _topoT = 0.48;
  double _nextAt = 5.5;
  int _epoch = 1;

  void tick(double t, {required bool frozen, required bool reduce}) {
    if (frozen) return;
    const dt = 1 / 60;
    final phaseRate = reduce ? 0.012 : 0.028;
    globalPhase += phaseRate * dt;
    const speeds = [0.055, -0.04, 0.07, -0.09];
    for (var i = 0; i < 4; i++) {
      layerPhase[i] += speeds[i] * (reduce ? 0.4 : 1) * dt;
    }
    final follow = reduce ? 0.015 : 0.028;
    foldAmount += (_foldT - foldAmount) * follow;
    lobeDepth += (_lobeT - lobeDepth) * follow;
    outerReach += (_outerT - outerReach) * follow;
    flowSpeed += (_flowT - flowSpeed) * follow;
    topologyMix += (_topoT - topologyMix) * follow;
    if (t >= _nextAt) {
      _pick(_epoch++);
      _nextAt = t + 4 + _hash01(_epoch * 17.3) * 5;
    }
    flowSpeed *= reduce ? 0.35 : 1;
  }

  void _pick(int epoch) {
    double h(double k) => _hash01(epoch * 13.1 + k * 7.7);
    _foldT = 0.28 + 0.27 * h(1);
    _lobeT = 0.08 + 0.10 * h(2);
    _outerT = 0.72 + 0.18 * h(3);
    _flowT = 0.09 + 0.17 * h(4);
    _topoT = 0.35 + 0.27 * h(5);
    waveOrderA = (2 + (h(7) * 3).floor()).toDouble();
    waveOrderB = (4 + (h(8) * 3).floor()).toDouble();
  }
}

/// Returns polar (r, thetaLocal in 0..1) in base half-sector — from CurveRenderer.
Offset _polarLocal({
  required double u,
  required double curveId,
  required double layer,
  required double rnd,
  required double phase,
  required double time,
  required double volume,
  required double treble,
  required double foldAmount,
  required double lobeDepth,
  required double outerReach,
  required double flowSpeed,
  required double topologyMix,
  required double waveOrderA,
  required double waveOrderB,
  required List<double> layerPhase,
  required double tipSharpness,
  required double bendFrequency,
  required double bendAmplitude,
  required double radialStretch,
}) {
  final lp = layer < 0.5
      ? layerPhase[0]
      : layer < 1.5
          ? layerPhase[1]
          : layer < 2.5
              ? layerPhase[2]
              : layerPhase[3];
  final morph = time * flowSpeed;
  final n0 = _smoothNoise3(curveId * 0.17, u * 1.35, morph * 0.065);
  final correlated = (n0 - 0.5) * 2.0;
  final inner = layer < 0.5 ? 1.0 : 0.0;
  final outer = layer >= 2.5 ? 1.0 : 0.0;
  final middle = 1.0 - inner - outer;

  const pitchW = 0.55;
  const autoW = 1.0 - pitchW;
  final bendFreq = waveOrderA * 0.45 * (1 - pitchW) + bendFrequency * pitchW;
  final bendAmp = lobeDepth * 1.1 * (1 - pitchW) + bendAmplitude * pitchW;
  final tipPow = 1.0 * (1 - pitchW) + (0.78 + 0.77 * tipSharpness) * pitchW;
  final stretch = 1.0 * (1 - pitchW) + radialStretch * pitchW;
  final foldDrive = foldAmount * (1 - pitchW) + bendAmplitude * 1.35 * pitchW;

  final waveA = math.sin(u * _tau * bendFreq + morph * 0.23 + curveId + phase);
  final waveB =
      math.cos(u * _tau * bendFreq * 1.35 - morph * 0.17 + layer + lp);
  double warp;
  if (layer < 0.5) {
    warp = 0.035 + foldDrive * 0.04;
  } else if (layer < 1.5) {
    warp = 0.06 + foldDrive * 0.08;
  } else if (layer < 2.5) {
    warp = 0.08 + bendAmp * 0.55 * 0.55;
  } else {
    warp = 0.10 + bendAmp * 0.7 * 0.55;
  }

  var home = (curveId * 0.61803398875 + rnd * 0.05 + layer * 0.11) % 1.0;
  if (home < 0) home += 1;
  home = 0.03 + 0.94 * home;
  final rail = ((curveId * 0.37 + rnd) % 1.0) < 0.5 ? 0.05 : 0.95;
  final seedA = home * (1 - outer * 0.7) + rail * outer * 0.7;
  var seedB = (home + 0.33).clamp(0.03, 0.97);
  seedB = seedB * (1 - outer * 0.55) + (1 - rail) * outer * 0.55;
  seedB = seedB.clamp(0.03, 0.97);

  var maxWobble = 0.08 - 0.035 * tipSharpness;
  maxWobble *= 1.0 - 0.6 * ((seedA - 0.5).abs() * 2.0);
  maxWobble = math.max(maxWobble, 0.025);

  var angTravel = 0.42 - 0.20 * tipSharpness;
  angTravel = angTravel * (1 - outer) + (0.92 - 0.22 * tipSharpness) * outer;

  double layerBase(double lid, double ch) {
    final t = (ch * 0.917 + 0.13) % 1.0;
    final tt = t < 0 ? t + 1 : t;
    if (lid < 0.5) return 0.06 + 0.10 * tt;
    if (lid < 1.5) return 0.16 + 0.14 * tt;
    if (lid < 2.5) return 0.30 + 0.20 * tt;
    return 0.52 + (outerReach.clamp(0.62, 0.92) - 0.52) * tt;
  }

  // Topology A
  final baseA = layerBase(layer, curveId + rnd);
  var spanA = inner * 0.10 +
      middle * 0.24 +
      outer * 0.38;
  spanA *= 1.18 - 0.36 * tipSharpness;
  final uRad = math.pow(u.clamp(0.0, 1.0), tipPow).toDouble();
  var rA = baseA + spanA * uRad * stretch;
  rA += autoW * warp * (0.58 * waveA + 0.42 * waveB);
  rA += pitchW * bendAmp * (0.55 * waveA + 0.35 * waveB) * (1.15 - 0.6 * tipSharpness);
  rA += autoW * correlated * (0.014 + middle * 0.02);

  var foldAng = (0.05 + foldDrive * 0.10) *
      math.sin(u * _tau * bendFreq + phase + morph * 0.15);
  foldAng = foldAng.clamp(-maxWobble, maxWobble);
  final sweepDir = ((curveId * 0.5 + rnd * 0.3) % 1.0) < 0.5 ? 1.0 : -1.0;
  var thA = seedA +
      sweepDir * angTravel * (u - 0.5) +
      autoW * 0.04 * math.sin(u * _tau * 1.5 + phase + morph * 0.12) +
      pitchW * foldAng;
  thA = thA.clamp(0.02, 0.98);

  // Topology B
  final baseB = layerBase(layer, curveId + rnd + 3.1);
  var reachB = (0.22 + 0.40 * (outer * 0.85 + middle * 0.55)) * stretch;
  reachB *= 1.15 - 0.27 * tipSharpness;
  var rB = baseB + reachB * math.pow(u, 0.72 + 0.63 * tipSharpness).toDouble();
  rB += autoW * warp * 0.75 * math.sin(u * _tau * bendFreq * 0.5 + morph * 0.19 + phase);
  rB += pitchW * bendAmp * 0.7 * math.sin(u * _tau * bendFreq + morph * 0.19 + phase);
  var thB = seedB + angTravel * (u - 0.5);
  if (outer > 0.5) {
    final outerU = ((curveId * 0.5) % 1.0) < 0.5 ? u : 1 - u;
    thB = 0.04 + 0.92 * outerU;
  }
  thB += (pitchW * foldAng * 0.7).clamp(-maxWobble, maxWobble);
  thB = thB.clamp(0.02, 0.98);

  var topo = topologyMix * (1 - pitchW * 0.45) + tipSharpness * 0.45 * pitchW * 0.45 + 0.3;
  topo = topo.clamp(0.25, 0.75);
  var r = rA + (rB - rA) * topo;
  var th = thA + (thB - thA) * topo;

  final volWave = volume * (0.012 + tipSharpness * 0.006);
  r += volWave * math.sin(morph * 0.31 + lp + u * _tau);
  r *= 1.0 + volume * 0.045;
  th += treble * 0.012 * math.sin(u * _tau * bendFreq * 2.2 - morph * 0.2 + curveId);
  r += treble * 0.008 * outer * math.sin(u * _tau * 4.0 + phase);

  if (outer > 0.5) {
    r *= 0.92 + 0.08 * math.sin(lp * 0.7 + curveId * 1.3 + morph * 0.05);
  }
  final rMax = outerReach * stretch + outer * (0.20 - 0.08 * tipSharpness);
  r = r.clamp(0.04, rMax);
  th = th.clamp(0.02, 0.98);
  return Offset(r, th);
}

Offset _toCartesian({
  required Offset polar,
  required int sectorCount,
  required int rotationIndex,
  required double mirrorSign,
  required double globalPhase,
  required double aspect,
  required double scale,
}) {
  final sectorAngle = _tau / sectorCount;
  final sectorHalf = sectorAngle * 0.5;
  final theta = rotationIndex * sectorAngle +
      mirrorSign * (polar.dy * sectorHalf) +
      globalPhase;
  var x = math.cos(theta) * polar.dx * 1.25 * scale;
  var y = math.sin(theta) * polar.dx * 1.25 * scale;
  x /= math.max(aspect, 0.001);
  return Offset(x, y);
}

class _SoundVisualPainter extends CustomPainter {
  _SoundVisualPainter({
    required this.seed,
    required this.mode,
    required this.time,
    required this.morph,
    this.amplitude = 0.2,
    this.showProgressRing = false,
    this.progress = 0,
  });

  final int seed;
  final SoundVisualMode mode;
  final double time;
  final _Morph morph;
  final double amplitude;
  final bool showProgressRing;
  final double progress;

  static const _sectorCount = 6;
  static const _samples = 28;
  static const _strands = 4;
  static const _curvesPerLayer = [1, 2, 2, 2];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = math.min(size.width, size.height) * 0.48;
    final aspect = size.width / math.max(size.height, 1);
    final volume = switch (mode) {
      SoundVisualMode.recording || SoundVisualMode.playback =>
        amplitude.clamp(0.05, 1.0),
      SoundVisualMode.paused => 0.08,
      SoundVisualMode.complete => 0.12,
      SoundVisualMode.idle =>
        math.max(0.04, 0.04 + 0.03 * math.sin(time * 0.8)),
    };
    final tip = mode == SoundVisualMode.recording
        ? 0.35 + volume * 0.25
        : 0.42;
    final bendAmp = 0.08 + volume * 0.1;
    final treble = mode == SoundVisualMode.recording ? volume * 0.55 : 0.15;

    // Soft core glow (mint)
    canvas.drawCircle(
      Offset(cx, cy),
      scale * 0.55,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.10 + volume * 0.12),
            AppColors.accentDark.withValues(alpha: 0.04),
            Colors.transparent,
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: scale)),
    );

    var curveIndex = 0;
    for (var layer = 0; layer < 4; layer++) {
      final nCurves = _curvesPerLayer[layer];
      final lw = morph.layerWeight[layer.clamp(0, 3)];
      for (var c = 0; c < nCurves; c++) {
        final curveId = curveIndex + 0.17 + seed * 0.001;
        final phase = ((c * 0.618 + layer * 1.7) % 1.0) * math.pi * 2;
        var rnd = math.sin(curveId * 12.9898) * 43758.5453;
        rnd = rnd - rnd.floorToDouble();

        for (var s = 0; s < _strands; s++) {
          final strandOffset = s - (_strands - 1) * 0.5;
          final lineRole = strandOffset.abs() < 0.6 ? 0.0 : 1.0;
          final alphaBase = (lineRole < 0.5 ? 0.28 : 0.14) * lw;
          final color = Color.lerp(
            const Color(0xFF4FA9E8),
            AppColors.accent,
            (layer / 3).clamp(0.0, 1.0),
          )!;
          final paint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = lineRole < 0.5 ? 1.05 : 0.7
            ..strokeCap = StrokeCap.round
            ..color = color.withValues(
              alpha: (alphaBase * (0.72 + volume * 0.4)).clamp(0.04, 0.38),
            );

          for (var rot = 0; rot < _sectorCount; rot++) {
            for (final mirror in [1.0, -1.0]) {
              final path = Path();
              for (var i = 0; i < _samples; i++) {
                final u = i / (_samples - 1);
                final pol = _polarLocal(
                  u: u,
                  curveId: curveId,
                  layer: layer.toDouble(),
                  rnd: rnd,
                  phase: phase,
                  time: time,
                  volume: volume,
                  treble: treble,
                  foldAmount: morph.foldAmount,
                  lobeDepth: morph.lobeDepth,
                  outerReach: morph.outerReach,
                  flowSpeed: morph.flowSpeed,
                  topologyMix: morph.topologyMix,
                  waveOrderA: morph.waveOrderA.toDouble(),
                  waveOrderB: morph.waveOrderB.toDouble(),
                  layerPhase: morph.layerPhase,
                  tipSharpness: tip,
                  bendFrequency: 2.5 + tip * 2,
                  bendAmplitude: bendAmp,
                  radialStretch: 1.0 + volume * 0.06,
                );

                // Normal offset for parallel strand
                final du = 1.0 / (_samples - 1);
                final polA = _polarLocal(
                  u: (u - du).clamp(0.0, 1.0),
                  curveId: curveId,
                  layer: layer.toDouble(),
                  rnd: rnd,
                  phase: phase,
                  time: time,
                  volume: volume,
                  treble: treble,
                  foldAmount: morph.foldAmount,
                  lobeDepth: morph.lobeDepth,
                  outerReach: morph.outerReach,
                  flowSpeed: morph.flowSpeed,
                  topologyMix: morph.topologyMix,
                  waveOrderA: morph.waveOrderA.toDouble(),
                  waveOrderB: morph.waveOrderB.toDouble(),
                  layerPhase: morph.layerPhase,
                  tipSharpness: tip,
                  bendFrequency: 2.5 + tip * 2,
                  bendAmplitude: bendAmp,
                  radialStretch: 1.0 + volume * 0.06,
                );
                final polB = _polarLocal(
                  u: (u + du).clamp(0.0, 1.0),
                  curveId: curveId,
                  layer: layer.toDouble(),
                  rnd: rnd,
                  phase: phase,
                  time: time,
                  volume: volume,
                  treble: treble,
                  foldAmount: morph.foldAmount,
                  lobeDepth: morph.lobeDepth,
                  outerReach: morph.outerReach,
                  flowSpeed: morph.flowSpeed,
                  topologyMix: morph.topologyMix,
                  waveOrderA: morph.waveOrderA.toDouble(),
                  waveOrderB: morph.waveOrderB.toDouble(),
                  layerPhase: morph.layerPhase,
                  tipSharpness: tip,
                  bendFrequency: 2.5 + tip * 2,
                  bendAmplitude: bendAmp,
                  radialStretch: 1.0 + volume * 0.06,
                );

                final p = _toCartesian(
                  polar: pol,
                  sectorCount: _sectorCount,
                  rotationIndex: rot,
                  mirrorSign: mirror,
                  globalPhase: morph.globalPhase,
                  aspect: aspect,
                  scale: 1,
                );
                final pA = _toCartesian(
                  polar: polA,
                  sectorCount: _sectorCount,
                  rotationIndex: rot,
                  mirrorSign: mirror,
                  globalPhase: morph.globalPhase,
                  aspect: aspect,
                  scale: 1,
                );
                final pB = _toCartesian(
                  polar: polB,
                  sectorCount: _sectorCount,
                  rotationIndex: rot,
                  mirrorSign: mirror,
                  globalPhase: morph.globalPhase,
                  aspect: aspect,
                  scale: 1,
                );
                final tx = (pB.dx - pA.dx) * aspect;
                final ty = pB.dy - pA.dy;
                final len = math.sqrt(tx * tx + ty * ty) + 1e-5;
                final nx = -ty / len;
                final ny = tx / len;
                final spacing = 0.012 * (1 + pol.dx * 0.35);
                final ox = nx * strandOffset * spacing;
                final oy = ny * strandOffset * spacing;
                final screen = Offset(cx + (p.dx + ox) * scale, cy + (p.dy + oy) * scale);
                if (i == 0) {
                  path.moveTo(screen.dx, screen.dy);
                } else {
                  path.lineTo(screen.dx, screen.dy);
                }
              }
              canvas.drawPath(path, paint);
            }
          }
        }
        curveIndex++;
      }
    }

    // Sparse beads along outer arcs
    final beadPaint = Paint()..color = AppColors.accentHighlight.withValues(alpha: 0.22 + volume * 0.2);
    for (var i = 0; i < 10; i++) {
      final u = (i * 0.173 + time * 0.03) % 1.0;
      final pol = _polarLocal(
        u: u,
        curveId: 2.17 + i * 0.3,
        layer: 3,
        rnd: _hash01(i + seed * 0.01),
        phase: i * 0.7,
        time: time,
        volume: volume,
        treble: treble,
        foldAmount: morph.foldAmount,
        lobeDepth: morph.lobeDepth,
        outerReach: morph.outerReach,
        flowSpeed: morph.flowSpeed,
        topologyMix: morph.topologyMix,
        waveOrderA: morph.waveOrderA.toDouble(),
        waveOrderB: morph.waveOrderB.toDouble(),
        layerPhase: morph.layerPhase,
        tipSharpness: tip,
        bendFrequency: 3,
        bendAmplitude: bendAmp,
        radialStretch: 1.05,
      );
      final p = _toCartesian(
        polar: pol,
        sectorCount: _sectorCount,
        rotationIndex: i % _sectorCount,
        mirrorSign: i.isEven ? 1 : -1,
        globalPhase: morph.globalPhase,
        aspect: aspect,
        scale: 1,
      );
      canvas.drawCircle(Offset(cx + p.dx * scale, cy + p.dy * scale), 1.4, beadPaint);
    }

    if (showProgressRing) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: scale * 0.92),
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0, 1),
        false,
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SoundVisualPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.mode != mode ||
      oldDelegate.amplitude != amplitude ||
      oldDelegate.progress != progress;
}

class SoundVisualCanvas extends StatefulWidget {
  const SoundVisualCanvas({
    super.key,
    required this.seed,
    this.active = false,
    this.dark = true,
    this.mode,
    this.amplitude = 0.2,
    this.showProgressRing = false,
    this.progress = 0,
  });

  final int seed;
  final bool active;
  final bool dark;
  final SoundVisualMode? mode;
  final double amplitude;
  final bool showProgressRing;
  final double progress;

  @override
  State<SoundVisualCanvas> createState() => _SoundVisualCanvasState();
}

class _SoundVisualCanvasState extends State<SoundVisualCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _morph = _Morph();
  final _start = DateTime.now();

  SoundVisualMode get _mode =>
      widget.mode ??
      (widget.active ? SoundVisualMode.recording : SoundVisualMode.idle);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    if (_mode != SoundVisualMode.complete) {
      _controller.repeat();
    } else {
      _controller.value = 0.2;
    }
  }

  @override
  void didUpdateWidget(covariant SoundVisualCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode || oldWidget.active != widget.active) {
      if (_mode == SoundVisualMode.complete) {
        _controller.stop();
      } else if (!_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _mode == SoundVisualMode.complete
            ? 8.0 + widget.seed % 5
            : DateTime.now().difference(_start).inMilliseconds / 1000.0;
        _morph.tick(
          t,
          frozen: _mode == SoundVisualMode.paused ||
              _mode == SoundVisualMode.complete ||
              reduce,
          reduce: reduce,
        );
        return CustomPaint(
          painter: _SoundVisualPainter(
            seed: widget.seed,
            mode: reduce ? SoundVisualMode.complete : _mode,
            time: t,
            morph: _morph,
            amplitude: widget.amplitude,
            showProgressRing: widget.showProgressRing,
            progress: widget.progress,
          ),
          child: const SizedBox.expand(),
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(180, 180),
          painter: _NfcRipplePainter(
            t: widget.active ? _controller.value : 0.4,
          ),
        );
      },
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
