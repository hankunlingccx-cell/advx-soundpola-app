import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/audio_features.dart';
import '../theme/app_colors.dart';
import '../visual/audio_feature_timeline.dart';
import 'kaleido_linear_engine.dart';

enum SoundVisualMode { idle, recording, paused, complete, playback }

/// Live SoundPola visual — Q1 pure-circle particle ribbons, Canvas-mirrored
/// to the other three quadrants (inspired by visuallization/ Axis Field).
///
/// **Performance:** ticker runs only while [animate] is true (or auto for
/// recording / playback / paused). Idle / complete paint a frozen frame and
/// do not drive 60fps setState.
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
    /// `null` = auto (live modes only). Force `true` for splash breath etc.
    this.animate,
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
  final bool? animate;

  @override
  State<SoundVisualCanvas> createState() => _SoundVisualCanvasState();
}

class _SoundVisualCanvasState extends State<SoundVisualCanvas>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late KaleidoLinearEngine _engine;
  Duration _lastElapsed = Duration.zero;
  VisualQuality _tier = VisualQuality.medium;
  final _frameTimes = <double>[];
  int _paintEpoch = 0;
  double _pinchBase = 1.0;
  double _fpsAccum = 0;

  SoundVisualMode get _mode =>
      widget.mode ??
      (widget.active ? SoundVisualMode.recording : SoundVisualMode.idle);

  bool get _isLive =>
      _mode == SoundVisualMode.recording || _mode == SoundVisualMode.playback;

  bool get _wantsTicker => _tickerWanted(
        mode: _mode,
        animate: widget.animate,
      );

  static bool _tickerWanted({
    required SoundVisualMode mode,
    required bool? animate,
  }) {
    if (animate != null) return animate;
    return mode == SoundVisualMode.recording ||
        mode == SoundVisualMode.playback ||
        mode == SoundVisualMode.paused;
  }

  static SoundVisualMode _resolveMode({
    required SoundVisualMode? mode,
    required bool active,
  }) =>
      mode ?? (active ? SoundVisualMode.recording : SoundVisualMode.idle);

  @override
  void initState() {
    super.initState();
    _tier = _wantsTicker ? VisualQuality.medium : VisualQuality.low;
    _engine = KaleidoLinearEngine(seed: widget.seed)
      ..configureQuality(
        _wantsTicker
            ? VisualQualityProfile.forTier(_tier)
            : VisualQualityProfile.idle,
      );
    _ticker = createTicker(_onTick);
    _settleStaticOrStart();
  }

  @override
  void didUpdateWidget(covariant SoundVisualCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed) {
      final zoom = _engine.zoom;
      final phase = _engine.userPhase;
      _engine = KaleidoLinearEngine(seed: widget.seed)
        ..configureQuality(
          _wantsTicker
              ? VisualQualityProfile.forTier(_tier)
              : VisualQualityProfile.idle,
        )
        ..zoom = zoom
        ..userPhase = phase;
    }
    final oldWanted = _tickerWanted(
      mode: _resolveMode(mode: oldWidget.mode, active: oldWidget.active),
      animate: oldWidget.animate,
    );
    if (oldWanted != _wantsTicker ||
        oldWidget.mode != widget.mode ||
        oldWidget.active != widget.active ||
        oldWidget.animate != widget.animate ||
        oldWidget.seed != widget.seed) {
      _settleStaticOrStart();
    } else if (!_wantsTicker &&
        (oldWidget.showProgressRing != widget.showProgressRing ||
            oldWidget.progress != widget.progress)) {
      _paintEpoch++;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _settleStaticOrStart() {
    if (_wantsTicker) {
      if (!_ticker.isActive) {
        _lastElapsed = Duration.zero;
        _fpsAccum = 0;
        _ticker.start();
      }
      return;
    }
    if (_ticker.isActive) _ticker.stop();
    _lastElapsed = Duration.zero;
    // Frozen deterministic pose — one paint, no continuous setState.
    _engine.time = 5.0 + (widget.seed % 11) * 0.07;
    _engine.flowPhase = (_engine.time * 0.08) % 1.0;
    _engine.configureQuality(VisualQualityProfile.idle);
    final breath = 0.05 + widget.amplitude * 0.04;
    _engine.updateAudio(
      AudioFeatures(
        rms: breath,
        gatedRms: breath,
        fastEnvelope: breath,
        slowEnvelope: breath,
        spectralCentroid: 0.35,
      ),
      1 / 30,
    );
    _paintEpoch++;
    if (mounted) setState(() {});
  }

  void _onTick(Duration elapsed) {
    if (!_wantsTicker) {
      _ticker.stop();
      return;
    }

    final dtMs = _lastElapsed == Duration.zero
        ? 16.0
        : (elapsed - _lastElapsed).inMicroseconds / 1000.0;
    _lastElapsed = elapsed;
    final dt = (dtMs / 1000.0).clamp(0.0, 0.05);

    // Cap paint rate to profile targetFps (still advance engine time).
    final targetFps = VisualQualityProfile.forTier(_tier).targetFps;
    _fpsAccum += dt;
    final minDt = 1.0 / targetFps.clamp(20.0, 60.0);
    final shouldPaint = _fpsAccum >= minDt;
    if (shouldPaint) _fpsAccum = 0;

    _frameTimes.add(dt);
    if (_frameTimes.length > 45) _frameTimes.removeAt(0);
    if (_frameTimes.length >= 20) {
      final avg = _frameTimes.reduce((a, b) => a + b) / _frameTimes.length;
      final fps = 1.0 / avg.clamp(0.008, 0.1);
      final next = fps < 38
          ? VisualQuality.low
          : (fps < 50 ? VisualQuality.medium : VisualQuality.high);
      if (next != _tier) {
        _tier = next;
        _engine.configureQuality(VisualQualityProfile.forTier(_tier));
      }
    }

    final f = _resolveFeatures();
    _engine.tick(dt);
    _engine.updateAudio(f, dt);

    if (!shouldPaint) return;
    _paintEpoch++;
    if (mounted) setState(() {});
  }

  AudioFeatures _resolveFeatures() {
    if (_isLive) {
      final f = widget.features?.value;
      final vol = (widget.liveVolume?.value ?? widget.amplitude).clamp(0.0, 1.0);
      if (f != null) {
        // Analyzer may under-report while amplitude meter is lively — lift
        // envelopes so the pattern clearly follows mic energy.
        final e = math.max(
          math.max(f.gatedRms, f.fastEnvelope),
          vol,
        );
        if (e <= 0.001 && vol <= 0.001) return f;
        return AudioFeatures(
          rms: math.max(f.rms, vol),
          gatedRms: e,
          fastEnvelope: math.max(f.fastEnvelope, e),
          slowEnvelope: math.max(f.slowEnvelope, e * 0.85),
          bass: math.max(f.bass, e * 0.55),
          lowMid: math.max(f.lowMid, e * 0.6),
          mid: math.max(f.mid, e * 0.7),
          highMid: math.max(f.highMid, e * 0.45),
          treble: math.max(f.treble, e * 0.35),
          spectralCentroid: f.spectralCentroid,
          spectralFlux: math.max(f.spectralFlux, (e - f.slowEnvelope).abs()),
          onset: math.max(f.onset, vol > f.slowEnvelope + 0.12 ? vol : 0),
          zeroCrossingRate: f.zeroCrossingRate,
          pitch: f.pitch,
          confidence: f.confidence,
          agcGain: f.agcGain,
          noiseFloor: f.noiseFloor,
          trackedPeak: f.trackedPeak,
          spectrum: f.spectrum,
        );
      }
      return AudioFeatures(
        rms: vol,
        gatedRms: vol,
        fastEnvelope: vol,
        slowEnvelope: vol * 0.85,
        bass: vol * 0.5,
        mid: vol * 0.7,
        treble: vol * 0.4,
        spectralCentroid: 0.35 + vol * 0.25,
        pitch: 0.35 + vol * 0.3,
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTickerMode();
  }

  void _syncTickerMode() {
    final enabled = TickerMode.valuesOf(context).enabled;
    if (!enabled && _ticker.isActive) {
      _ticker.stop();
    } else if (enabled && _wantsTicker && !_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onScaleStart: _wantsTicker
            ? (_) {
                _pinchBase = _engine.zoom;
              }
            : null,
        onScaleUpdate: _wantsTicker
            ? (d) {
                if (d.pointerCount >= 2) {
                  _engine.setZoom(_pinchBase * d.scale);
                } else {
                  _engine.applyManualDelta(
                    d.focalPointDelta.dx,
                    d.focalPointDelta.dy,
                  );
                }
              }
            : null,
        onDoubleTap: _wantsTicker ? _engine.resetAutoSpin : null,
        child: CustomPaint(
          painter: _KaleidoPainter(
            engine: _engine,
            epoch: _paintEpoch,
            showProgressRing: widget.showProgressRing,
            progress: widget.progress,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _KaleidoPainter extends CustomPainter {
  _KaleidoPainter({
    required this.engine,
    required this.epoch,
    required this.showProgressRing,
    required this.progress,
  });

  final KaleidoLinearEngine engine;
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
  bool shouldRepaint(covariant _KaleidoPainter old) =>
      old.epoch != epoch ||
      old.showProgressRing != showProgressRing ||
      old.progress != progress;
}

/// Offline bake — same 4-quadrant linear engine as live canvas.
class SoundVisualOffscreen {
  SoundVisualOffscreen({
    required this.seed,
    this.quality = VisualQuality.medium,
  }) : _engine = KaleidoLinearEngine(seed: seed) {
    _engine.configureQuality(VisualQualityProfile.forTier(quality));
  }

  final int seed;
  final VisualQuality quality;
  final KaleidoLinearEngine _engine;

  void seek(AudioFeatureTimeline timeline, int timeMs, {required double dt}) {
    final f = timeline.sampleAt(timeMs);
    final t = timeMs / 1000.0;
    _engine.time = t + (seed % 11) * 0.001;
    _engine.flowPhase = (_engine.time * 0.08) % 1.0;
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

/// NFC detect ripple (Press flow).
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
