import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../audio/audio_features.dart';
import '../theme/app_colors.dart';

/// Deterministic geometric type on the sphere surface.
enum SphereGeom {
  filledCircle,
  hollowCircle,
  filledSquare,
  hollowSquare,
  diamond,
  cross,
  slash,
  doubleSlash,
  nineGrid,
  boxDot,
}

/// Precomputed lattice point (immutable base + mutable local energy).
class SpherePoint {
  SpherePoint({
    required this.lat,
    required this.lon,
    required this.ox,
    required this.oy,
    required this.oz,
    required this.specIndex,
    required this.geom,
    required this.seed,
    required this.rot0,
    required this.sizeBias,
    required this.colorBias,
  });

  final int lat;
  final int lon;
  final double ox;
  final double oy;
  final double oz;
  final int specIndex;
  final SphereGeom geom;
  final int seed;
  final double rot0;
  final double sizeBias;
  final double colorBias;

  double localEnergy = 0;
}

/// PixMusic-style pseudo-3D geometric SPHERE for SoundPola.
/// Audio analysis stays outside; feed [AudioFeatures] each frame.
class SphereVisualEngine {
  SphereVisualEngine({
    required this.seed,
    this.latitudeCount = 24,
    this.longitudeCount = 28,
  }) {
    _buildLattice();
  }

  final int seed;
  int latitudeCount;
  int longitudeCount;

  late List<SpherePoint> points;
  late Float32List _sx;
  late Float32List _sy;
  late Float32List _sz;
  late Float32List _ss;
  late Int32List _order;

  double time = 0;
  double autoRotX = 0;
  double autoRotY = 0;
  double userRotX = 0;
  double userRotY = 0;
  double velX = 0;
  double velY = 0;
  double zoom = 1.0;
  bool autoSpin = true;

  double energy = 0;
  double peak = 0;
  double timbre = 0.35;
  double onsetBurst = 0;
  List<double> spectrum = const [];

  final _fill = Paint()..style = PaintingStyle.fill;
  final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final _bg = Paint()..color = const Color(0xFF000000);

  static const _accent = Color(0xFF63E0CB);
  static const _deepTeal = Color(0xFF1A6B5E);
  static const _cyanBlue = Color(0xFF4DB8E8);
  static const _softViolet = Color(0xFF8B7AD6);

  void configureQuality(VisualQualityProfile q) {
    if (q.particleCount >= 600) {
      latitudeCount = 24;
      longitudeCount = 28;
    } else if (q.particleCount >= 400) {
      latitudeCount = 20;
      longitudeCount = 24;
    } else {
      latitudeCount = 16;
      longitudeCount = 20;
    }
    _buildLattice();
  }

  void _buildLattice() {
    final n = latitudeCount * longitudeCount;
    points = List<SpherePoint>.generate(n, (i) {
      final lat = i ~/ longitudeCount;
      final lon = i % longitudeCount;
      final theta = lat / (latitudeCount - 1) * math.pi;
      final phi = lon / longitudeCount * math.pi * 2.0;
      final ox = math.sin(theta) * math.cos(phi);
      final oy = math.cos(theta);
      final oz = math.sin(theta) * math.sin(phi);
      final h = _hash(seed, lat, lon);
      final geom = SphereGeom.values[h % SphereGeom.values.length];
      final specIndex =
          (lat * longitudeCount + lon) % AudioFeatures.spectrumBinCount;
      return SpherePoint(
        lat: lat,
        lon: lon,
        ox: ox,
        oy: oy,
        oz: oz,
        specIndex: specIndex,
        geom: geom,
        seed: h,
        rot0: ((h >> 8) & 0xFF) / 255.0 * math.pi,
        sizeBias: 0.85 + ((h >> 16) & 0xFF) / 255.0 * 0.35,
        colorBias: ((h >> 24) & 0xFF) / 255.0,
      );
    }, growable: false);
    _sx = Float32List(n);
    _sy = Float32List(n);
    _sz = Float32List(n);
    _ss = Float32List(n);
    _order = Int32List(n);
    for (var i = 0; i < n; i++) {
      _order[i] = i;
    }
    autoRotX = ((seed % 97) / 97.0) * math.pi * 0.4;
    autoRotY = ((seed % 131) / 131.0) * math.pi * 0.6;
  }

  static int _hash(int seed, int a, int b) {
    var x = seed ^ (a * 374761393) ^ (b * 668265263);
    x = (x ^ (x >> 13)) * 1274126177;
    return x & 0x7fffffff;
  }

  void applyManualDelta(double dx, double dy) {
    userRotY += dx * 0.008;
    userRotX += dy * 0.008;
    velY = dx * 0.02;
    velX = dy * 0.02;
    autoSpin = false;
  }

  void applyInertia(double dt) {
    if (autoSpin) return;
    userRotX += velX * dt;
    userRotY += velY * dt;
    velX *= math.pow(0.08, dt).toDouble();
    velY *= math.pow(0.08, dt).toDouble();
    if (velX.abs() < 0.01 && velY.abs() < 0.01) {
      velX = 0;
      velY = 0;
    }
  }

  void resetAutoSpin() {
    autoSpin = true;
    velX = 0;
    velY = 0;
  }

  void setZoom(double z) {
    zoom = z.clamp(0.8, 1.3);
  }

  void updateAudio(AudioFeatures f, double dt) {
    spectrum = f.spectrum;
    final live = f.fastEnvelope > 0.001
        ? f.fastEnvelope
        : (f.gatedRms > 0.001 ? f.gatedRms : f.rms);
    energy = _ar(energy, live.clamp(0.0, 1.0), 0.02, 0.16, dt);
    peak = _ar(peak, f.trackedPeak.clamp(0.0, 1.0), 0.03, 0.2, dt);
    timbre = _ar(timbre, f.spectralCentroid.clamp(0.0, 1.0), 0.06, 0.25, dt);

    final onset = f.onset > 0.22 ? f.onset : 0.0;
    if (onset > onsetBurst) {
      onsetBurst = onset;
    } else {
      onsetBurst = _ar(onsetBurst, 0, 0.05, 0.28, dt);
    }

    final idle = 0.035 +
        math.sin(time * 0.7) * 0.008 +
        math.sin(time * 0.23) * 0.006;
    final drive = math.max(energy, idle);

    for (final p in points) {
      final local = _localSpectrum(p.specIndex);
      final target = (local * 0.75 + drive * 0.25).clamp(0.0, 1.0);
      p.localEnergy = _ar(p.localEnergy, target, 0.018, 0.14, dt);
    }
  }

  double _localSpectrum(int index) {
    if (spectrum.isEmpty) return energy;
    final n = spectrum.length;
    var sum = 0.0;
    var w = 0.0;
    for (var k = -2; k <= 2; k++) {
      final i = (index + k + n * 8) % n;
      final ww = 3 - k.abs().toDouble();
      sum += spectrum[i] * ww;
      w += ww;
    }
    return (sum / w).clamp(0.0, 1.0);
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

  void tick(double dt) {
    time += dt;
    applyInertia(dt);
    if (autoSpin) {
      autoRotX = time * 0.4;
      autoRotY = time * 0.6;
    }
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
    final baseRadius = size.shortestSide * 0.34 * zoom;
    final radius = baseRadius * (0.9 + energy * 0.3 + onsetBurst * 0.18);
    final cameraDistance = radius * 3.0;

    final rotX = autoRotX + userRotX;
    final rotY = autoRotY + userRotY;
    final cosX = math.cos(rotX);
    final sinX = math.sin(rotX);
    final cosY = math.cos(rotY);
    final sinY = math.sin(rotY);

    final n = points.length;
    final unit = size.shortestSide / 320.0;
    for (var i = 0; i < n; i++) {
      final p = points[i];
      final x = p.ox * radius;
      final y = p.oy * radius;
      final z = p.oz * radius;

      final y1 = y * cosX - z * sinX;
      final z1 = y * sinX + z * cosX;
      final x2 = x * cosY + z1 * sinY;
      final z2 = -x * sinY + z1 * cosY;
      final y2 = y1;

      final perspective = cameraDistance / (cameraDistance - z2);
      _sx[i] = cx + x2 * perspective;
      _sy[i] = cy + y2 * perspective;
      _sz[i] = z2;

      final depth = ((z2 / radius) + 1.0) * 0.5;
      final audioSize =
          (0.65 + p.localEnergy * 1.8 + energy * 0.45) * p.sizeBias;
      _ss[i] = (2.2 + depth * 3.8) * audioSize * unit;
    }

    for (var i = 0; i < n; i++) {
      _order[i] = i;
    }
    _shellSortByZ(n);

    for (var k = 0; k < n; k++) {
      final i = _order[k];
      final p = points[i];
      final depth = ((_sz[i] / radius) + 1.0) * 0.5;
      final alpha = (0.18 + depth * 0.72).clamp(0.08, 0.95);
      if (depth < 0.12 && _ss[i] < 1.2) continue;

      final color = _colorFor(p, depth);
      _drawGeom(
        canvas,
        p,
        Offset(_sx[i], _sy[i]),
        _ss[i],
        color.withValues(alpha: (color.a * alpha).clamp(0.0, 1.0)),
        depth,
      );
    }

    if (showProgressRing) {
      final r = size.shortestSide * 0.46;
      _stroke
        ..color = AppColors.accent.withValues(alpha: 0.2)
        ..strokeWidth = 2;
      canvas.drawCircle(Offset(cx, cy), r, _stroke);
      _stroke
        ..color = AppColors.accent.withValues(alpha: 0.85)
        ..strokeWidth = 2.5;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        -math.pi / 2,
        progress.clamp(0.0, 1.0) * math.pi * 2,
        false,
        _stroke,
      );
    }
  }

  void _shellSortByZ(int n) {
    for (var gap = n >> 1; gap > 0; gap >>= 1) {
      for (var i = gap; i < n; i++) {
        final tmp = _order[i];
        final tz = _sz[tmp];
        var j = i;
        while (j >= gap && _sz[_order[j - gap]] > tz) {
          _order[j] = _order[j - gap];
          j -= gap;
        }
        _order[j] = tmp;
      }
    }
  }

  Color _colorFor(SpherePoint p, double depth) {
    final t = timbre;
    Color base;
    if (t < 0.33) {
      base = Color.lerp(_deepTeal, _accent, t / 0.33 + p.colorBias * 0.15)!;
    } else if (t < 0.66) {
      base = Color.lerp(
        _accent,
        Colors.white,
        (t - 0.33) / 0.33 * 0.55 + p.colorBias * 0.1,
      )!;
    } else {
      base = Color.lerp(
        _cyanBlue,
        _softViolet,
        (t - 0.66) / 0.34 * 0.35 + p.colorBias * 0.08,
      )!;
    }
    if (onsetBurst > 0.45 && p.localEnergy > 0.55 && depth > 0.55) {
      final w = ((onsetBurst - 0.45) / 0.55).clamp(0.0, 1.0);
      base = Color.lerp(base, Colors.white, w * 0.85)!;
    }
    return Color.lerp(base.withValues(alpha: 0.7), base, depth)!;
  }

  void _drawGeom(
    Canvas canvas,
    SpherePoint p,
    Offset c,
    double s,
    Color color,
    double depth,
  ) {
    final rot = p.rot0 + p.localEnergy * 0.9 + energy * 0.35;
    final lw = (0.7 + p.localEnergy * 1.4 + energy * 0.5).clamp(0.6, 2.4) *
        (s / 4.0).clamp(0.55, 1.4);
    final filledBoost = p.localEnergy > 0.42;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rot);

    switch (p.geom) {
      case SphereGeom.filledCircle:
        _fill.color = color;
        canvas.drawCircle(Offset.zero, s * 0.55, _fill);
      case SphereGeom.hollowCircle:
        _stroke
          ..color = color
          ..strokeWidth = lw;
        canvas.drawCircle(Offset.zero, s * 0.55, _stroke);
        if (filledBoost && depth > 0.5) {
          _fill.color = color.withValues(alpha: color.a * 0.35);
          canvas.drawCircle(Offset.zero, s * 0.22, _fill);
        }
      case SphereGeom.filledSquare:
        _fill.color = color;
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: s, height: s),
          _fill,
        );
      case SphereGeom.hollowSquare:
        _stroke
          ..color = color
          ..strokeWidth = lw;
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: s, height: s),
          _stroke,
        );
      case SphereGeom.diamond:
        final path = Path()
          ..moveTo(0, -s * 0.65)
          ..lineTo(s * 0.55, 0)
          ..lineTo(0, s * 0.65)
          ..lineTo(-s * 0.55, 0)
          ..close();
        if (filledBoost) {
          _fill.color = color;
          canvas.drawPath(path, _fill);
        } else {
          _stroke
            ..color = color
            ..strokeWidth = lw;
          canvas.drawPath(path, _stroke);
        }
      case SphereGeom.cross:
        _stroke
          ..color = color
          ..strokeWidth = lw;
        canvas.drawLine(Offset(-s * 0.55, 0), Offset(s * 0.55, 0), _stroke);
        canvas.drawLine(Offset(0, -s * 0.55), Offset(0, s * 0.55), _stroke);
      case SphereGeom.slash:
        _stroke
          ..color = color
          ..strokeWidth = lw;
        canvas.drawLine(
          Offset(-s * 0.5, s * 0.5),
          Offset(s * 0.5, -s * 0.5),
          _stroke,
        );
      case SphereGeom.doubleSlash:
        _stroke
          ..color = color
          ..strokeWidth = lw * 0.85;
        canvas.drawLine(
          Offset(-s * 0.55, s * 0.35),
          Offset(s * 0.35, -s * 0.55),
          _stroke,
        );
        canvas.drawLine(
          Offset(-s * 0.35, s * 0.55),
          Offset(s * 0.55, -s * 0.35),
          _stroke,
        );
      case SphereGeom.nineGrid:
        _fill.color = color;
        final step = s * 0.32;
        for (var gy = -1; gy <= 1; gy++) {
          for (var gx = -1; gx <= 1; gx++) {
            final boost = (gx == 0 && gy == 0) ? 1.15 : 0.75;
            canvas.drawCircle(
              Offset(gx * step, gy * step),
              s * 0.12 * boost * (0.7 + p.localEnergy),
              _fill,
            );
          }
        }
      case SphereGeom.boxDot:
        _stroke
          ..color = color
          ..strokeWidth = lw;
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: s, height: s),
          _stroke,
        );
        _fill.color = color;
        canvas.drawCircle(Offset.zero, s * 0.18, _fill);
    }
    canvas.restore();
  }
}
