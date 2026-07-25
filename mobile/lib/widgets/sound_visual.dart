import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/audio_features.dart';
import '../theme/app_colors.dart';
import '../visual/audio_feature_timeline.dart';
import 'sphere_visual_engine.dart';

enum SoundVisualMode { idle, recording, paused, complete, playback }

/// Live SoundPola SPHERE visual — PixMusic-style geometric sphere.
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
  final ValueListenable<double>? liveVolume;
  final bool showProgressRing;
  final double progress;

  @override
  State<SoundVisualCanvas> createState() => _SoundVisualCanvasState();
}

class _SoundVisualCanvasState extends State<SoundVisualCanvas>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late SphereVisualEngine _engine;
  Duration _lastElapsed = Duration.zero;
  VisualQuality _tier = VisualQuality.high;
  final _frameTimes = <double>[];
  int _paintEpoch = 0;
  double _pinchBase = 1.0;

  SoundVisualMode get _mode =>
      widget.mode ??
      (widget.active ? SoundVisualMode.recording : SoundVisualMode.idle);

  bool get _isLive =>
      _mode == SoundVisualMode.recording || _mode == SoundVisualMode.playback;

  @override
  void initState() {
    super.initState();
    _engine = SphereVisualEngine(seed: widget.seed);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant SoundVisualCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed) {
      final zoom = _engine.zoom;
      final urx = _engine.userRotX;
      final ury = _engine.userRotY;
      _engine = SphereVisualEngine(seed: widget.seed)
        ..configureQuality(VisualQualityProfile.forTier(_tier))
        ..zoom = zoom
        ..userRotX = urx
        ..userRotY = ury;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dtMs = _lastElapsed == Duration.zero
        ? 16.0
        : (elapsed - _lastElapsed).inMicroseconds / 1000.0;
    _lastElapsed = elapsed;
    final dt = (dtMs / 1000.0).clamp(0.0, 0.05);

    _frameTimes.add(dt);
    if (_frameTimes.length > 45) _frameTimes.removeAt(0);
    if (_frameTimes.length >= 20) {
      final avg =
          _frameTimes.reduce((a, b) => a + b) / _frameTimes.length;
      final fps = 1.0 / avg.clamp(0.008, 0.1);
      final next = fps < 42
          ? VisualQuality.low
          : (fps < 52 ? VisualQuality.medium : VisualQuality.high);
      if (next != _tier) {
        _tier = next;
        _engine.configureQuality(VisualQualityProfile.forTier(_tier));
      }
    }

    final f = _resolveFeatures();
    _engine.tick(dt);
    _engine.updateAudio(f, dt);

    // Freeze complete mode at deterministic time from seed.
    if (_mode == SoundVisualMode.complete) {
      _engine.time = 5.0 + (widget.seed % 11) * 0.07;
      _engine.autoRotX = _engine.time * 0.4;
      _engine.autoRotY = _engine.time * 0.6;
    }

    _paintEpoch++;
    if (mounted) setState(() {});
  }

  AudioFeatures _resolveFeatures() {
    if (_isLive) {
      final f = widget.features?.value;
      if (f != null) return f;
      final v = widget.liveVolume?.value ?? widget.amplitude;
      return AudioFeatures(
        rms: v,
        gatedRms: v,
        fastEnvelope: v,
        slowEnvelope: v * 0.85,
        mid: v,
      );
    }
    if (_mode == SoundVisualMode.paused) {
      final v = widget.liveVolume?.value ?? widget.amplitude * 0.35;
      return AudioFeatures(
        rms: v,
        gatedRms: v,
        fastEnvelope: v,
        slowEnvelope: v,
      );
    }
    // Idle / complete: soft deterministic breath (engine also adds idleEnergy)
    final breath = 0.04 +
        0.02 * math.sin(_engine.time * 0.55) +
        widget.amplitude * 0.05;
    return AudioFeatures(
      rms: breath,
      gatedRms: breath,
      fastEnvelope: breath,
      slowEnvelope: breath,
      spectralCentroid: 0.35,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: (d) {
        _pinchBase = _engine.zoom;
      },
      onScaleUpdate: (d) {
        if (d.pointerCount >= 2) {
          _engine.setZoom(_pinchBase * d.scale);
        } else {
          _engine.applyManualDelta(d.focalPointDelta.dx, d.focalPointDelta.dy);
        }
      },
      onDoubleTap: _engine.resetAutoSpin,
      child: CustomPaint(
        painter: _SpherePainter(
          engine: _engine,
          epoch: _paintEpoch,
          showProgressRing: widget.showProgressRing,
          progress: widget.progress,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SpherePainter extends CustomPainter {
  _SpherePainter({
    required this.engine,
    required this.epoch,
    required this.showProgressRing,
    required this.progress,
  });

  final SphereVisualEngine engine;
  final int epoch;
  final bool showProgressRing;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    engine.paint(
      canvas,
      size,
      showProgressRing: showProgressRing,
      progress: progress,
    );
  }

  @override
  bool shouldRepaint(covariant _SpherePainter old) =>
      old.epoch != epoch ||
      old.showProgressRing != showProgressRing ||
      old.progress != progress;
}

/// Offline SPHERE bake — same engine as live canvas.
class SoundVisualOffscreen {
  SoundVisualOffscreen({
    required this.seed,
    this.quality = VisualQuality.medium,
  }) : _engine = SphereVisualEngine(seed: seed) {
    _engine.configureQuality(VisualQualityProfile.forTier(quality));
  }

  final int seed;
  final VisualQuality quality;
  final SphereVisualEngine _engine;

  void seek(AudioFeatureTimeline timeline, int timeMs, {required double dt}) {
    final f = timeline.sampleAt(timeMs);
    final t = timeMs / 1000.0;
    _engine.time = t + (seed % 11) * 0.001;
    _engine.autoSpin = true;
    _engine.autoRotX = _engine.time * 0.4;
    _engine.autoRotY = _engine.time * 0.6;
    _engine.updateAudio(f, dt);
  }

  Future<ui.Image> renderImage(int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(width.toDouble(), height.toDouble());
    _engine.paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    return image;
  }

  void warmUp(AudioFeatureTimeline timeline, int untilMs, double stepMs) {
    var t = 0;
    final dt = stepMs / 1000.0;
    while (t < untilMs) {
      seek(timeline, t, dt: dt);
      t += stepMs.round();
    }
  }
}

/// NFC detect ripple (unchanged public API for Press flow).
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
