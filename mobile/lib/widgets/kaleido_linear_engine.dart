import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../audio/audio_features.dart';
import '../theme/app_colors.dart';

/// Arrangement kind for a seeded particle line bundle in Q1.
enum _LineKind { radial, arc, chord }

/// One parallel particle line-bundle authored in Q1 (mirrored to 4 quadrants).
class _Ribbon {
  _Ribbon({
    required this.id,
    required this.layer,
    required this.kind,
    required this.baseTheta,
    required this.r0,
    required this.r1,
    required this.parallel,
    required this.spacing,
    required this.particles,
    required this.phase,
    required this.bend,
    required this.flowDir,
    required this.specU,
    required this.sizeBias,
  });

  final int id;
  final int layer;
  final _LineKind kind;
  final double baseTheta;
  final double r0;
  final double r1;
  final int parallel;
  final double spacing;
  final int particles;
  final double phase;
  final double bend;
  final double flowDir;
  final double specU;
  final double sizeBias;
}

/// Axis-Field inspired linear particle field with strict 4-quadrant mirror.
///
/// Geometry is authored once in Q1 as pure circles only. The other three
/// quadrants are produced by Canvas scale mirrors of that single Q1 picture.
class KaleidoLinearEngine {
  KaleidoLinearEngine({required this.seed, int ribbonBudget = 56}) {
    rebuild(ribbonBudget: ribbonBudget);
  }

  final int seed;
  late List<_Ribbon> _ribbons;

  double time = 0;
  double flowPhase = 0;
  double energy = 0;
  double bass = 0.12;
  double mid = 0.15;
  double treble = 0.1;
  double centroid = 0.35;
  double flux = 0;
  double onset = 0;
  double zcr = 0.2;
  /// Continuous volume→style morph 0–1 (quiet↔loud). Not overall scale.
  double volumeStyle = 0.28;
  /// Volume-driven field rotation (radians, accumulates while loud).
  double audioSpin = 0;
  /// Volume-driven fold amount 0–1 (quiet flat ↔ loud folded).
  double audioFold = 0;
  List<double> spectrum = const [];

  double userPhase = 0;
  double userFold = 0;
  double velPhase = 0;
  double zoom = 1.0;

  final _fill = Paint()..style = PaintingStyle.fill;
  final _bg = Paint()..color = const Color(0xFF000000);

  static const _accent = Color(0xFF63E0CB);
  static const _deep = Color(0xFF1A6B5E);
  static const _cyan = Color(0xFF4DB8E8);
  static const _violet = Color(0xFF8B7AD6);
  static const _pink = Color(0xFFD4A0C8);

  /// Quiet / mid / loud — rotate/fold character is the main visible morph.
  static const _lookA = _StyleLook(
    sharpness: 0.15,
    density: 0.75,
    beadScale: 1.2,
    flowMul: 0.4,
    foldMul: 0.35,
    waveAmp: 0.4,
    structureShift: 0.0,
    spinMul: 0.25,
    tint: _deep,
  );
  static const _lookB = _StyleLook(
    sharpness: 0.55,
    density: 1.05,
    beadScale: 0.95,
    flowMul: 1.15,
    foldMul: 1.15,
    waveAmp: 1.15,
    structureShift: 0.5,
    spinMul: 1.0,
    tint: _accent,
  );
  static const _lookC = _StyleLook(
    sharpness: 1.0,
    density: 1.4,
    beadScale: 0.7,
    flowMul: 1.9,
    foldMul: 1.85,
    waveAmp: 1.75,
    structureShift: 1.0,
    spinMul: 2.1,
    tint: _pink,
  );

  void configureQuality(VisualQualityProfile q) {
    final budget = q.particleCount >= 600
        ? 64
        : (q.particleCount >= 400 ? 48 : 32);
    rebuild(ribbonBudget: budget);
  }

  void rebuild({required int ribbonBudget}) {
    final rng = _Rng(seed);
    final list = <_Ribbon>[];
    var id = 0;
    final layerCounts = [
      (ribbonBudget * 0.16).round().clamp(5, 14),
      (ribbonBudget * 0.28).round().clamp(8, 20),
      (ribbonBudget * 0.34).round().clamp(10, 24),
      (ribbonBudget * 0.22).round().clamp(7, 16),
    ];
    for (var layer = 0; layer < 4; layer++) {
      final n = layerCounts[layer];
      for (var i = 0; i < n; i++) {
        final t = (i + 0.5) / n;
        // Mix arrangement kinds so each quadrant reads as many linear rows.
        final kindRoll = rng.next();
        final kind = kindRoll < 0.52
            ? _LineKind.radial
            : (kindRoll < 0.78 ? _LineKind.arc : _LineKind.chord);

        final baseTheta = t * (math.pi * 0.5) + (rng.next() - 0.5) * 0.1;
        final rPair = switch (layer) {
          0 => (0.05 + rng.next() * 0.07, 0.17 + rng.next() * 0.08),
          1 => (0.14 + rng.next() * 0.08, 0.34 + rng.next() * 0.10),
          2 => (0.28 + rng.next() * 0.10, 0.56 + rng.next() * 0.12),
          _ => (0.46 + rng.next() * 0.10, 0.74 + rng.next() * 0.16),
        };

        final parallel = switch (kind) {
          _LineKind.radial => switch (layer) {
              0 => 4 + (rng.next() * 4).floor(),
              1 => 6 + (rng.next() * 6).floor(),
              2 => 8 + (rng.next() * 8).floor(),
              _ => 5 + (rng.next() * 7).floor(),
            },
          _LineKind.arc => 3 + (rng.next() * 5).floor() + layer,
          _LineKind.chord => 4 + (rng.next() * 6).floor() + (layer ~/ 2),
        };

        final particles = switch (kind) {
          _LineKind.radial => switch (layer) {
              0 => 14 + (rng.next() * 10).floor(),
              1 => 18 + (rng.next() * 14).floor(),
              2 => 22 + (rng.next() * 16).floor(),
              _ => 16 + (rng.next() * 14).floor(),
            },
          _LineKind.arc => 16 + (rng.next() * 18).floor() + layer * 2,
          _LineKind.chord => 14 + (rng.next() * 16).floor() + layer,
        };

        list.add(_Ribbon(
          id: id++,
          layer: layer,
          kind: kind,
          baseTheta: baseTheta.clamp(0.02, math.pi * 0.5 - 0.02),
          r0: rPair.$1,
          r1: rPair.$2,
          parallel: parallel,
          spacing: switch (kind) {
            _LineKind.radial => 0.0035 + rng.next() * 0.006,
            _LineKind.arc => 0.005 + rng.next() * 0.008,
            _LineKind.chord => 0.004 + rng.next() * 0.007,
          },
          particles: particles,
          phase: rng.next() * math.pi * 2,
          bend: 0.3 + rng.next() * 1.0,
          flowDir: rng.next() > 0.5 ? 1.0 : -1.0,
          specU: rng.next(),
          sizeBias: 0.7 + rng.next() * 0.55,
        ));
      }
    }
    _ribbons = list;
  }

  void applyManualDelta(double dx, double dy) {
    userPhase += dx * 0.004;
    userFold += dy * 0.003;
    userFold = userFold.clamp(-0.45, 0.45);
    velPhase = dx * 0.012;
  }

  void applyInertia(double dt) {
    userPhase += velPhase * dt;
    velPhase *= math.pow(0.05, dt).toDouble();
    if (velPhase.abs() < 0.002) velPhase = 0;
    userFold = _ar(userFold, 0, 0.4, 0.4, dt);
  }

  void resetAutoSpin() {
    userPhase = 0;
    userFold = 0;
    velPhase = 0;
    audioSpin = 0;
    audioFold = 0;
  }

  void setZoom(double z) => zoom = z.clamp(0.8, 1.3);

  void updateAudio(AudioFeatures f, double dt) {
    spectrum = f.spectrum;
    final live = f.fastEnvelope > 0.001
        ? f.fastEnvelope
        : (f.gatedRms > 0.001 ? f.gatedRms : f.rms);
    energy = _ar(energy, live.clamp(0.0, 1.0), 0.018, 0.14, dt);
    bass = _ar(bass, f.bass, 0.03, 0.16, dt);
    mid = _ar(mid, f.mid, 0.025, 0.12, dt);
    treble = _ar(treble, f.treble, 0.02, 0.1, dt);
    centroid = _ar(centroid, f.spectralCentroid, 0.06, 0.2, dt);
    flux = _ar(flux, f.spectralFlux, 0.02, 0.12, dt);
    final onsetT = f.onset > 0.18 ? f.onset : 0.0;
    onset = onsetT > onset ? onsetT : _ar(onset, 0, 0.05, 0.24, dt);
    zcr = _ar(zcr, f.zeroCrossingRate, 0.04, 0.14, dt);

    // Volume→style: ignore tiny level noise; morph when loudness meaningfully changes.
    final targetStyle = _volumeToStyle(energy, onset);
    final rising = targetStyle > volumeStyle;
    volumeStyle = _ar(
      volumeStyle,
      targetStyle,
      rising ? 0.06 : 0.14,
      rising ? 0.06 : 0.14,
      dt,
    );
    // Fold tracks volume tightly — this is the main silhouette morph.
    audioFold = _ar(
      audioFold,
      targetStyle,
      rising ? 0.05 : 0.12,
      rising ? 0.05 : 0.12,
      dt,
    );
  }

  void tick(double dt) {
    time += dt;
    applyInertia(dt);
    final idle = 0.035 +
        math.sin(time * 0.55) * 0.008 +
        math.sin(time * 0.19) * 0.005;
    final drive = math.max(energy, idle);
    final look = _styleLook(volumeStyle);
    final flowSpeed = 0.06 *
        (1.0 + drive * 1.2 + look.flowMul * 0.55 + onset * 0.45);
    flowPhase = (flowPhase + dt * flowSpeed) % 1.0;
    // Continuous field spin — quiet almost still, loud spins + folds open.
    final spinSpeed = 0.12 +
        audioFold * 1.35 * look.spinMul +
        onset * 0.55 +
        drive * 0.25;
    audioSpin += dt * spinSpeed;
  }

  /// Map mic energy to style progress. Soft thresholds so only clear volume
  /// shifts cross quiet↔mid↔loud looks.
  static double _volumeToStyle(double energy, double onset) {
    final e = (energy + onset * 0.28).clamp(0.0, 1.0);
    // More responsive: quiet below ~0.08; loud saturates ~0.58.
    return _smoothstep(0.08, 0.58, e);
  }

  /// Adjacent A↔B / B↔C morph from continuous volumeStyle.
  static _StyleLook _styleLook(double style01) {
    final p = style01.clamp(0.0, 1.0);
    if (p <= 0.5) {
      return _StyleLook.lerp(_lookA, _lookB, _smoothstep(0.0, 0.5, p));
    }
    return _StyleLook.lerp(_lookB, _lookC, _smoothstep(0.5, 1.0, p));
  }

  static double _smoothstep(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  void paint(
    Canvas canvas,
    Size size, {
    bool showProgressRing = false,
    double progress = 0,
  }) {
    canvas.drawRect(Offset.zero & size, _bg);
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final scale = size.shortestSide * 0.46 * zoom;

    final idle = 0.035 + math.sin(time * 0.55) * 0.008;
    final drive = math.max(energy, idle);
    final look = _styleLook(volumeStyle);
    final shapeT = _smoothstep(0.05, 0.9, volumeStyle);
    final foldAmt = (audioFold * 0.72 + look.foldMul * 0.28).clamp(0.0, 1.0);
    // Big fold/twist — quiet nearly flat, loud strongly folded (not scaled).
    final geo = _soft(drive) * 0.22;
    final fold = (0.08 + foldAmt * 0.95 + userFold.abs() * 0.55).clamp(0.06, 1.15);
    final outerBoost = 0.992 + foldAmt * 0.02 + onset * 0.012;
    final tipSharp = 0.12 + look.sharpness * 0.9 + foldAmt * 0.2;
    final waveMul = look.waveAmp * (0.55 + foldAmt * 0.9);
    final struct = look.structureShift;
    // Differential twist: outer layers lag/lead for a folding-open feel.
    final twistBase = foldAmt * 0.55 + userFold * 0.35;
    final spinDraw = audioSpin * 0.55 + userPhase * 0.4;

    // Build Q1 once (pure circles). Coordinates: +x right, +y up from origin.
    // Cull rect keeps mirrored Picture draws finite (avoids unbounded glitches).
    final extent = scale * 1.15;
    final recorder = ui.PictureRecorder();
    final q1 = Canvas(
      recorder,
      Rect.fromLTRB(-extent, -extent, extent, extent),
    );

    for (final rib in _ribbons) {
      final local = _sampleSpec(rib.specU);
      final localSoft = _soft(local);
      final layerW = switch (rib.layer) {
        0 => 0.7 + bass * 0.25,
        1 => 0.65 + mid * 0.3,
        2 => 0.6 + mid * 0.2 + treble * 0.15,
        _ => 0.55 + treble * 0.3 + zcr * 0.1,
      };
      final bright =
          (0.18 + drive * 0.55 + localSoft * 0.22 + onset * 0.22) * layerW;
      final color = _color(bright.clamp(0.0, 1.0), rib.layer);
      final half = (rib.parallel - 1) * 0.5;
      final layerTwist =
          twistBase * (rib.layer - 1.5) * 0.22 + spinDraw * 0.08 * rib.flowDir;

      for (var p = 0; p < rib.parallel; p++) {
        final offNorm = (p - half) *
            rib.spacing *
            (0.92 + geo * 0.08 + localSoft * 0.06) /
            look.density.clamp(0.55, 1.7);

        for (var i = 0; i < rib.particles; i++) {
          final u = rib.particles <= 1 ? 0.5 : i / (rib.particles - 1);
          final styleDrift =
              math.sin(time * (0.28 + look.flowMul * 0.7) + rib.phase) *
                  (0.02 + shapeT * 0.08 + struct * 0.05);
          final flowU = (u +
                  flowPhase * rib.flowDir * (0.35 + foldAmt * 0.45) *
                      look.flowMul +
                  rib.phase * 0.02 +
                  userPhase * 0.2 +
                  audioSpin * 0.04 * rib.flowDir +
                  styleDrift)
              .remainder(1.0);
          final fu = flowU < 0 ? flowU + 1.0 : flowU;

          final xy = _pointQ1(
            fu,
            rib,
            offNorm: offNorm,
            fold: fold,
            outerBoost: outerBoost,
            tipSharp: tipSharp,
            local: localSoft,
            drive: geo,
            waveMul: waveMul,
            structureShift: struct,
            twist: layerTwist,
            foldAmt: foldAmt,
          );
          final px = xy.$1 * scale;
          final py = xy.$2 * scale;

          final bead = (0.58 +
                  localSoft * 0.12 +
                  geo * 0.1 +
                  (1.0 - (p - half).abs() / (half + 0.01)) * 0.06) *
              (0.85 + rib.sizeBias * 0.15) *
              look.beadScale *
              (size.shortestSide / 420.0);
          final a = (0.12 + bright * 0.62).clamp(0.08, 0.72) *
              (0.6 + (1 - (p - half).abs() / (half + 1)) * 0.4);
          _fill.color = color.withValues(alpha: a);
          q1.drawCircle(Offset(px, -py), bead.clamp(0.22, 1.55), _fill);
        }
      }
    }

    final picture = recorder.endRecording();

    // Whole field rotates with volume; mirrors stay 4-fold symmetric.
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(spinDraw);
    canvas.drawPicture(picture); // Q1
    canvas.save();
    canvas.scale(-1, 1);
    canvas.drawPicture(picture); // Q2
    canvas.restore();
    canvas.save();
    canvas.scale(1, -1);
    canvas.drawPicture(picture); // Q4
    canvas.restore();
    canvas.save();
    canvas.scale(-1, -1);
    canvas.drawPicture(picture); // Q3
    canvas.restore();
    canvas.restore();
    picture.dispose();

    if (showProgressRing) {
      final r = size.shortestSide * 0.46;
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.accent.withValues(alpha: 0.2);
      canvas.drawCircle(Offset(cx, cy), r, stroke);
      stroke
        ..color = AppColors.accent.withValues(alpha: 0.85)
        ..strokeWidth = 2.5;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        -math.pi / 2,
        progress.clamp(0.0, 1.0) * math.pi * 2,
        false,
        stroke,
      );
    }
  }

  /// Returns normalized (x, y) in Q1 (x≥0, y≥0), including parallel offset.
  (double, double) _pointQ1(
    double u,
    _Ribbon rib, {
    required double offNorm,
    required double fold,
    required double outerBoost,
    required double tipSharp,
    required double local,
    required double drive,
    required double waveMul,
    required double structureShift,
    required double twist,
    required double foldAmt,
  }) {
    switch (rib.kind) {
      case _LineKind.radial:
        final polar = _polarRadial(
          u,
          rib,
          fold: fold,
          outerBoost: outerBoost,
          tipSharp: tipSharp,
          local: local,
          drive: drive,
          waveMul: waveMul,
          structureShift: structureShift,
          twist: twist,
          foldAmt: foldAmt,
        );
        final nx = -math.sin(polar.$2);
        final ny = math.cos(polar.$2);
        final x = polar.$1 * math.cos(polar.$2) + nx * offNorm;
        final y = polar.$1 * math.sin(polar.$2) + ny * offNorm;
        return (_clampQ1(x), _clampQ1(y));

      case _LineKind.arc:
        final rBase = ui.lerpDouble(rib.r0, rib.r1, 0.45 + local * 0.06)! *
            (0.995 + drive * 0.01);
        final foldRipple = math.sin(
              u * math.pi * (1.5 + foldAmt * 2.2) + rib.phase + time * 0.55,
            ) *
            (0.01 + fold * 0.055) *
            waveMul;
        final r = (rBase + offNorm) * (1.0 + foldRipple);
        final theta = ui.lerpDouble(0.04, math.pi * 0.5 - 0.04, u)! +
            twist +
            math.sin(u * math.pi * rib.bend +
                    flowPhase * math.pi * 2 * rib.flowDir) *
                (0.02 + fold * 0.12 + structureShift * 0.06) *
                waveMul +
            math.sin(u * math.pi) * foldAmt * 0.28 +
            userFold * 0.18 * math.sin(u * math.pi * 2);
        final th = theta.clamp(0.015, math.pi * 0.5 - 0.015);
        return (_clampQ1(r * math.cos(th)), _clampQ1(r * math.sin(th)));

      case _LineKind.chord:
        final span =
            0.22 + structureShift * 0.35 + rib.bend * 0.12 + foldAmt * 0.4;
        final x0 = rib.r0 * math.cos(rib.baseTheta + twist * 0.6);
        final y0 = rib.r0 * math.sin(rib.baseTheta + twist * 0.6);
        final x1 = rib.r1 * math.cos(rib.baseTheta + span + twist);
        final y1 = rib.r1 * math.sin(rib.baseTheta + span + twist);
        final ease = u * u * (3 - 2 * u);
        var x = ui.lerpDouble(x0, x1, ease)!;
        var y = ui.lerpDouble(y0, y1, ease)!;
        final dx = x1 - x0;
        final dy = y1 - y0;
        final len = math.sqrt(dx * dx + dy * dy).clamp(0.001, 2.0);
        final nx = -dy / len;
        final ny = dx / len;
        final freq = 1.0 + structureShift * 1.2 + foldAmt * 2.0;
        final wave = math.sin(
              u * math.pi * (freq + rib.bend) + time * 0.65 + rib.phase,
            ) *
            (0.008 + fold * 0.06) *
            waveMul;
        final crease = math.sin(u * math.pi) * foldAmt * 0.07;
        x += nx * (offNorm + wave + crease);
        y += ny * (offNorm + wave + crease);
        return (_clampQ1(x), _clampQ1(y));
    }
  }

  (double, double) _polarRadial(
    double u,
    _Ribbon rib, {
    required double fold,
    required double outerBoost,
    required double tipSharp,
    required double local,
    required double drive,
    required double waveMul,
    required double structureShift,
    required double twist,
    required double foldAmt,
  }) {
    final ease = u * u * (3 - 2 * u);
    var r = ui.lerpDouble(rib.r0, rib.r1 * outerBoost, ease)!;
    r *= 1.0 + (ease - 0.5) * tipSharp * 0.16;

    // Strong angular fold along the ray — reads as 旋转折叠, not scale.
    final wave = math.sin(
              u * math.pi * (1.0 + rib.bend + structureShift + foldAmt) +
                  time * 0.7 +
                  rib.phase,
            ) *
            (0.02 + fold * 0.14) *
            waveMul +
        math.sin(u * math.pi * (2.2 + foldAmt * 2.0) +
                flowPhase * math.pi * 2 * rib.flowDir) *
            (0.012 + local * 0.02 + tipSharp * 0.02) *
            waveMul;
    final lobe = math.sin(u * math.pi) *
        (0.015 + fold * 0.12 + onset * 0.04 + foldAmt * 0.18) *
        waveMul;
    var theta = rib.baseTheta +
        twist +
        wave +
        lobe +
        userFold * 0.22 * math.sin(u * math.pi) +
        math.sin(u * math.pi * 2 + audioSpin) * foldAmt * 0.12;
    theta += (foldAmt - 0.35) * 0.18 * math.sin(u * math.pi);
    theta = theta.clamp(0.015, math.pi * 0.5 - 0.015);
    r = r.clamp(0.02, 0.96) * (0.995 + drive * 0.012);
    return (r, theta);
  }

  double _clampQ1(double v) => v.clamp(0.004, 0.98);

  /// Soft-compress 0–1 so loud audio doesn't explode geometry.
  static double _soft(double x) {
    final t = x.clamp(0.0, 1.0);
    return t / (1.0 + t * 0.85);
  }

  Color _color(double bright, int layer) {
    final look = _styleLook(volumeStyle);
    // Volume style drives quiet teal → loud violet/pink; centroid is a light nudge.
    final t = (volumeStyle * 0.85 + centroid * 0.15).clamp(0.0, 1.0);
    Color base;
    if (t < 0.33) {
      base = Color.lerp(_deep, _cyan, t / 0.33)!;
    } else if (t < 0.66) {
      base = Color.lerp(_accent, _violet, (t - 0.33) / 0.33)!;
    } else {
      base = Color.lerp(_violet, _pink, (t - 0.66) / 0.34)!;
    }
    base = Color.lerp(base, look.tint, 0.32)!;
    if (onset > 0.5 && bright > 0.55 && layer >= 2) {
      base = Color.lerp(base, Colors.white, ((onset - 0.5) / 0.5) * 0.55)!;
    }
    return Color.lerp(base.withValues(alpha: 0.75), base, bright)!;
  }

  double _sampleSpec(double u) {
    if (spectrum.isEmpty) return energy;
    final n = spectrum.length;
    final x = u.clamp(0.0, 1.0) * (n - 1);
    final i0 = x.floor().clamp(0, n - 1);
    final i1 = (i0 + 1).clamp(0, n - 1);
    final f = x - i0;
    final iM = (i0 - 1 + n) % n;
    final iP = (i1 + 1) % n;
    return ((spectrum[iM] * 0.15 +
                spectrum[i0] * (0.35 * (1 - f) + 0.2) +
                spectrum[i1] * (0.35 * f + 0.2) +
                spectrum[iP] * 0.1))
        .clamp(0.0, 1.0);
  }

  static double _ar(
    double cur,
    double target,
    double attack,
    double release,
    double dt,
  ) {
    final tau = target > cur ? attack : release;
    final k = 1.0 - math.exp(-dt / tau.clamp(0.001, 2.0));
    return cur + (target - cur) * k;
  }
}

/// Continuous visual state for volume morph (quiet/mid/loud anchors).
class _StyleLook {
  const _StyleLook({
    required this.sharpness,
    required this.density,
    required this.beadScale,
    required this.flowMul,
    required this.foldMul,
    required this.waveAmp,
    required this.structureShift,
    required this.spinMul,
    required this.tint,
  });

  final double sharpness;
  final double density;
  final double beadScale;
  final double flowMul;
  final double foldMul;
  final double waveAmp;
  final double structureShift;
  final double spinMul;
  final Color tint;

  static _StyleLook lerp(_StyleLook a, _StyleLook b, double t) {
    final k = t.clamp(0.0, 1.0);
    return _StyleLook(
      sharpness: ui.lerpDouble(a.sharpness, b.sharpness, k)!,
      density: ui.lerpDouble(a.density, b.density, k)!,
      beadScale: ui.lerpDouble(a.beadScale, b.beadScale, k)!,
      flowMul: ui.lerpDouble(a.flowMul, b.flowMul, k)!,
      foldMul: ui.lerpDouble(a.foldMul, b.foldMul, k)!,
      waveAmp: ui.lerpDouble(a.waveAmp, b.waveAmp, k)!,
      structureShift: ui.lerpDouble(a.structureShift, b.structureShift, k)!,
      spinMul: ui.lerpDouble(a.spinMul, b.spinMul, k)!,
      tint: Color.lerp(a.tint, b.tint, k)!,
    );
  }
}

class _Rng {
  _Rng(int seed) : _s = seed & 0x7fffffff;
  int _s;
  double next() {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s / 0x7fffffff;
  }
}
