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
  double volumeStyle = 0.12;
  List<double> spectrum = const [];

  double userPhase = 0;
  double userFold = 0;
  double velPhase = 0;
  double zoom = 1.0;

  final _fill = Paint()..style = PaintingStyle.fill;
  final _bg = Paint()..color = const Color(0xFF000000);

  static const _accent = Color(0xFF63E0CB);
  static const _deep = Color(0xFF2E9B88);
  static const _cyan = Color(0xFF6BC8F2);
  static const _violet = Color(0xFFA090E8);
  static const _pink = Color(0xFFE8B8DC);

  /// Quiet / mid / loud styles — always lerp neighbors (never hard-cut).
  /// Wide A↔C deltas so loudness clearly reshapes the field (not just tint).
  static const _lookA = _StyleLook(
    sharpness: 0.06,
    density: 0.58,
    // Soft but still discrete circles — oversized beads fuse into sausages.
    beadScale: 1.12,
    flowMul: 0.32,
    foldMul: 0.55,
    waveAmp: 0.38,
    structureShift: 0.0,
    tint: _deep,
  );
  static const _lookB = _StyleLook(
    sharpness: 0.55,
    density: 1.12,
    beadScale: 0.92,
    flowMul: 1.25,
    foldMul: 1.15,
    waveAmp: 1.15,
    structureShift: 0.55,
    tint: _accent,
  );
  static const _lookC = _StyleLook(
    sharpness: 1.0,
    density: 1.72,
    beadScale: 0.48,
    flowMul: 2.35,
    foldMul: 1.55,
    waveAmp: 1.95,
    structureShift: 1.0,
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
  }

  void setZoom(double z) => zoom = z.clamp(0.8, 1.3);

  void updateAudio(AudioFeatures f, double dt) {
    spectrum = f.spectrum;
    // Primary driver = loudness only (fast envelope / gated RMS).
    // Slightly softer rise from near-silence so standby→active isn't a jolt.
    final live = math.max(f.fastEnvelope, f.gatedRms).clamp(0.0, 1.0);
    final fromRest = energy < 0.1;
    energy = _ar(energy, live, fromRest ? 0.07 : 0.016, 0.1, dt);
    bass = _ar(bass, f.bass, 0.025, 0.14, dt);
    mid = _ar(mid, f.mid, 0.02, 0.11, dt);
    treble = _ar(treble, f.treble, 0.018, 0.1, dt);
    centroid = _ar(centroid, f.spectralCentroid, 0.05, 0.16, dt);
    flux = _ar(flux, f.spectralFlux, 0.02, 0.1, dt);
    final onsetT = f.onset > 0.12 ? f.onset : 0.0;
    onset = onsetT > onset ? onsetT : _ar(onset, 0, 0.045, 0.2, dt);
    zcr = _ar(zcr, f.zeroCrossingRate, 0.035, 0.12, dt);

    // Style follows volume: quiet→A, mid→B, loud→C.
    // Lag behind energy so idle/quiet look morphs fluidly into mid/loud
    // (density, bead scale, tint) instead of snapping with the envelope.
    final targetStyle = _volumeToStyle(energy);
    final leaveQuiet = volumeStyle < 0.38 && targetStyle > volumeStyle;
    volumeStyle = _ar(
      volumeStyle,
      targetStyle,
      leaveQuiet ? 0.34 : 0.2,
      0.38,
      dt,
    );
  }

  void tick(double dt) {
    time += dt;
    applyInertia(dt);
    final vol = energy.clamp(0.0, 1.0);
    final look = _styleLook(volumeStyle);
    // Quiet ≈ crawl; loud ≈ sprint. Volume dominates speed.
    final flowSpeed = 0.018 +
        vol * vol * 0.42 * look.flowMul +
        vol * 0.08 +
        onset * 0.04 * vol;
    flowPhase = (flowPhase + dt * flowSpeed) % 1.0;
  }

  /// Loudness → style 0–1. Broad soft ramp so quiet→loud spans gradually.
  static double _volumeToStyle(double energy) {
    final s = _smoothstep(0.02, 0.7, energy.clamp(0.0, 1.0));
    return math.pow(s, 0.82).toDouble().clamp(0.0, 1.0);
  }

  /// Adjacent A↔B / B↔C morph from continuous volumeStyle.
  /// Linear within each half so leaving idle moves look immediately & evenly.
  static _StyleLook _styleLook(double style01) {
    final p = style01.clamp(0.0, 1.0);
    if (p <= 0.5) {
      return _StyleLook.lerp(_lookA, _lookB, p / 0.5);
    }
    return _StyleLook.lerp(_lookB, _lookC, (p - 0.5) / 0.5);
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

    // Volume gates how much the field moves / morphs (quiet = small & slow).
    final vol = energy.clamp(0.0, 1.0);
    final drive = _soft(vol);
    final look = _styleLook(volumeStyle);
    final shapeT = volumeStyle.clamp(0.0, 1.0);
    final amp = (0.12 + vol * 0.88).clamp(0.12, 1.0); // change size vs loudness
    final geo = drive * 0.7 * amp;
    final fold = (0.12 +
            look.foldMul * 0.42 * amp +
            userFold * 0.45 +
            shapeT * 0.12 * amp)
        .clamp(0.1, 0.95);
    final outerBoost = 0.994 + shapeT * 0.018 * amp + onset * 0.02 * vol;
    final tipSharp = 0.12 + (look.sharpness * 1.1 + shapeT * 0.2) * amp;
    final waveMul = look.waveAmp * amp;
    final struct = look.structureShift * amp;
    // 1 at idle/quiet → discrete round pearls; 0 at loud → denser fine beads.
    final quietPearl = (1.0 - shapeT).clamp(0.0, 1.0);
    final alongKeep = ui.lerpDouble(
      1.0,
      (0.78 / look.beadScale.clamp(0.5, 1.4)).clamp(0.4, 0.72),
      quietPearl,
    )!;

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
      // Brightness mainly from volume; spectrum / onset are light accents.
      final bright =
          (0.24 + vol * 0.72 + localSoft * 0.18 * vol + onset * 0.2 * vol) *
              layerW;
      final color = _color(bright.clamp(0.0, 1.0), rib.layer);
      final half = (rib.parallel - 1) * 0.5;

      for (var p = 0; p < rib.parallel; p++) {
        // Louder → denser parallel rows (tighter spacing), not overall zoom.
        final offNorm = (p - half) *
            rib.spacing *
            (0.9 + geo * 0.12 + localSoft * 0.08 * vol) /
            look.density.clamp(0.48, 1.9);

        // Quiet/idle: fewer samples along each ribbon so beads stay round pearls
        // instead of fusing into elongated strokes.
        final nAlong =
            math.max(5, (rib.particles * alongKeep).round());

        for (var i = 0; i < nAlong; i++) {
          final u = nAlong <= 1 ? 0.5 : i / (nAlong - 1);
          // Drift amount & rate follow volume (quiet almost still).
          final styleDrift =
              math.sin(time * (0.12 + vol * look.flowMul * 1.1) + rib.phase) *
                  (0.006 + vol * 0.12 + struct * 0.05);
          final flowU = (u +
                  flowPhase * rib.flowDir * (0.2 + vol * 0.45) * look.flowMul +
                  rib.phase * 0.02 +
                  userPhase * 0.15 +
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
          );
          // Skip outside Q1 — independent clamp would squash onto axes as streaks.
          if (xy == null) continue;
          final px = xy.$1 * scale;
          final py = xy.$2 * scale;

          // Bead character follows style (thick soft ↔ fine sharp), not balloon.
          // Idle slightly larger so each pearl reads as a circle, not a speck-line.
          final bead = (0.52 +
                  localSoft * 0.2 +
                  geo * 0.16 +
                  (1.0 - (p - half).abs() / (half + 0.01)) * 0.08) *
              (0.85 + rib.sizeBias * 0.15) *
              look.beadScale *
              (1.0 + quietPearl * 0.35) *
              (size.shortestSide / 380.0);
          final a = (0.2 + bright * 0.8).clamp(0.16, 0.96) *
              (0.55 + (1 - (p - half).abs() / (half + 1)) * 0.45);
          _fill.color = color.withValues(alpha: a);
          // Flutter y-down: store Q1 as (+px, -py) so +y math is screen-up.
          q1.drawCircle(
            Offset(px, -py),
            bead.clamp(0.35, 2.4 + quietPearl * 0.6),
            _fill,
          );
        }
      }
    }

    final picture = recorder.endRecording();

    // Draw Q1 once, then mirror with Canvas scale — do not recompute geometry.
    canvas.save();
    canvas.translate(cx, cy);
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
      // Progress arc only — no full-circle track stroke.
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AppColors.accent.withValues(alpha: 0.85)
        ..strokeCap = StrokeCap.round;
      final sweep = progress.clamp(0.0, 1.0) * math.pi * 2;
      if (sweep > 0.001) {
        canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: r),
          -math.pi / 2,
          sweep,
          false,
          stroke,
        );
      }
    }
  }

  /// Returns normalized (x, y) in Q1, or null if parallel offset left the quadrant.
  /// Null (skip) avoids axis-squash streaks from independent x/y clamps.
  (double, double)? _pointQ1(
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
  }) {
    final double x;
    final double y;
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
        );
        final nx = -math.sin(polar.$2);
        final ny = math.cos(polar.$2);
        x = polar.$1 * math.cos(polar.$2) + nx * offNorm;
        y = polar.$1 * math.sin(polar.$2) + ny * offNorm;

      case _LineKind.arc:
        // Quiet: smooth arcs; loud: more angular sweep + ripple.
        final rBase = ui.lerpDouble(rib.r0, rib.r1, 0.42 + local * 0.12)! *
            (0.99 + drive * 0.025);
        final r = (rBase + offNorm) *
            (1.0 +
                math.sin(u * math.pi * (2 + structureShift * 1.4) +
                        rib.phase +
                        time * 0.55) *
                    (0.014 + fold * 0.028) *
                    waveMul);
        final theta = ui.lerpDouble(0.04, math.pi * 0.5 - 0.04, u)! +
            math.sin(u * math.pi * rib.bend +
                    flowPhase * math.pi * 2 * rib.flowDir) *
                (0.032 + fold * 0.06 + structureShift * 0.055) *
                waveMul +
            userFold * 0.06 * math.sin(u * math.pi);
        final th = theta.clamp(0.015, math.pi * 0.5 - 0.015);
        x = r * math.cos(th);
        y = r * math.sin(th);

      case _LineKind.chord:
        // Quiet: soft bend; loud: sharper zig / higher-frequency warp.
        final span = 0.26 + structureShift * 0.34 + rib.bend * 0.18;
        final x0 = rib.r0 * math.cos(rib.baseTheta);
        final y0 = rib.r0 * math.sin(rib.baseTheta);
        final x1 = rib.r1 * math.cos(rib.baseTheta + span);
        final y1 = rib.r1 * math.sin(rib.baseTheta + span);
        final ease = u * u * (3 - 2 * u);
        final bx = ui.lerpDouble(x0, x1, ease)!;
        final by = ui.lerpDouble(y0, y1, ease)!;
        final dx = x1 - x0;
        final dy = y1 - y0;
        final len = math.sqrt(dx * dx + dy * dy).clamp(0.001, 2.0);
        final nx = -dy / len;
        final ny = dx / len;
        final freq = 1.15 + structureShift * 2.2;
        final wave = math.sin(
              u * math.pi * (freq + rib.bend) + time * 0.85 + rib.phase,
            ) *
            (0.012 + fold * 0.032) *
            waveMul;
        x = bx + nx * (offNorm + wave);
        y = by + ny * (offNorm + wave);
    }
    if (x < 0.002 || y < 0.002 || x > 0.99 || y > 0.99) return null;
    return (x, y);
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
  }) {
    final ease = u * u * (3 - 2 * u);
    var r = ui.lerpDouble(rib.r0, rib.r1 * outerBoost, ease)!;
    // Loud → pointed tips along radius (shape change, not zoom).
    r *= 1.0 + (ease - 0.5) * tipSharp * 0.28;

    final wave = math.sin(
              u * math.pi * (1.0 + rib.bend + structureShift * 1.1) +
                  time * 0.9 +
                  rib.phase,
            ) *
            (0.036 + fold * 0.07) *
            waveMul +
        math.sin(u * math.pi * (2.2 + structureShift * 1.8) +
                flowPhase * math.pi * 2 * rib.flowDir) *
            (0.016 + local * 0.028 + tipSharp * 0.02) *
            waveMul;
    final lobe =
        math.sin(u * math.pi) * (0.02 + fold * 0.055 + onset * 0.035) * waveMul;
    var theta =
        rib.baseTheta + wave + lobe + userFold * 0.07 * math.sin(u * math.pi);
    // Structure shift fans rays without ballooning the silhouette.
    theta += (structureShift - 0.5) * 0.09 * math.sin(u * math.pi * 2);
    theta = theta.clamp(0.015, math.pi * 0.5 - 0.015);
    r = r.clamp(0.02, 0.96) * (0.99 + drive * 0.028);
    return (r, theta);
  }

  /// Soft-compress 0–1 so peaks stay readable without flattening mids.
  static double _soft(double x) {
    final t = x.clamp(0.0, 1.0);
    return t / (1.0 + t * 0.4);
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
    if (onset > 0.35 && bright > 0.4 && layer >= 2) {
      base = Color.lerp(base, Colors.white, ((onset - 0.35) / 0.65) * 0.65)!;
    }
    return Color.lerp(base.withValues(alpha: 0.88), base, bright)!;
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
    final shape = (spectrum[iM] * 0.15 +
            spectrum[i0] * (0.35 * (1 - f) + 0.2) +
            spectrum[i1] * (0.35 * f + 0.2) +
            spectrum[iP] * 0.1)
        .clamp(0.0, 1.0);
    // Local spectrum only accents volume-driven brightness.
    return (energy * 0.55 + shape * energy * 0.45).clamp(0.0, 1.0);
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
    required this.tint,
  });

  final double sharpness;
  final double density;
  final double beadScale;
  final double flowMul;
  final double foldMul;
  final double waveAmp;
  final double structureShift;
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
