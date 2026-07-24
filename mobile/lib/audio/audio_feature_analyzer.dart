import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'audio_features.dart';

/// Off-UI-thread audio analysis.
///
/// Ingests amplitude (dBFS or 0–1) on the main isolate; FFT/RMS at ~28 Hz and
/// pitch at ~20 Hz run inside a worker isolate. UI only observes [features].
class AudioFeatureAnalyzer {
  AudioFeatureAnalyzer._(this._worker, this._toWorker);

  final Isolate _worker;
  final SendPort _toWorker;
  final ValueNotifier<AudioFeatures> features =
      ValueNotifier(AudioFeatures.silent);
  final ReceivePort _fromWorker = ReceivePort();
  StreamSubscription? _sub;
  bool _active = false;
  bool _disposed = false;

  static Future<AudioFeatureAnalyzer> spawn() async {
    final ready = ReceivePort();
    final worker = await Isolate.spawn(
      _analyzerMain,
      ready.sendPort,
      debugName: 'audio-feature-analyzer',
    );
    final toWorker = await ready.first as SendPort;
    ready.close();
    final analyzer = AudioFeatureAnalyzer._(worker, toWorker);
    analyzer._sub = analyzer._fromWorker.listen((msg) {
      if (msg is Map) {
        analyzer.features.value = AudioFeatures.fromMap(msg);
      }
    });
    toWorker.send({
      'cmd': 'init',
      'port': analyzer._fromWorker.sendPort,
    });
    return analyzer;
  }

  /// Push raw amplitude. Accepts dBFS (typical −60…0) or already-normalized 0–1.
  void pushAmplitude(double amp) {
    if (_disposed || !_active) return;
    _toWorker.send({'cmd': 'amp', 'v': amp, 't': DateTime.now().microsecondsSinceEpoch});
  }

  /// Idle / paused: stop analysis (worker idles; no feature spam).
  void setActive(bool active) {
    _active = active;
    if (_disposed) return;
    _toWorker.send({'cmd': 'active', 'v': active});
    if (!active) {
      features.value = AudioFeatures.silent;
    }
  }

  void dispose() {
    _disposed = true;
    _active = false;
    _sub?.cancel();
    _fromWorker.close();
    features.dispose();
    _toWorker.send({'cmd': 'dispose'});
    _worker.kill(priority: Isolate.immediate);
  }
}

// ─── Worker isolate ─────────────────────────────────────────────────────────

const _rmsHz = 28.0;
const _pitchHz = 20.0;
const _fftSize = 64;

void _analyzerMain(SendPort ready) {
  final inbox = ReceivePort();
  ready.send(inbox.sendPort);

  SendPort? out;
  var active = false;
  final ring = List<double>.filled(_fftSize, 0.1);
  var ringWrite = 0;
  var ringCount = 0;
  var prevNorm = 0.1;
  var onsetEnv = 0.0;
  var pitchHold = 0.45;
  var confidenceHold = 0.35;
  var lastRmsUs = 0;
  var lastPitchUs = 0;
  double emaSlow = 0.1, emaMed = 0.1, emaFast = 0.1;

  double normAmp(double v) {
    if (v <= 1.0 && v >= 0.0) return v;
    // dBFS → 0–1 (approx −60…0)
    return ((v + 60) / 60).clamp(0.0, 1.0);
  }

  void emit(AudioFeatures f) => out?.send(f.toMap());

  inbox.listen((msg) {
    if (msg is! Map) return;
    final cmd = msg['cmd'];
    switch (cmd) {
      case 'init':
        out = msg['port'] as SendPort;
      case 'active':
        active = msg['v'] == true;
        if (!active) {
          emit(AudioFeatures.silent);
          ringWrite = 0;
          ringCount = 0;
        }
      case 'dispose':
        inbox.close();
      case 'amp':
        if (!active || out == null) return;
        final now = msg['t'] as int? ?? DateTime.now().microsecondsSinceEpoch;
        final a = normAmp((msg['v'] as num).toDouble());
        ring[ringWrite] = a;
        ringWrite = (ringWrite + 1) % _fftSize;
        if (ringCount < _fftSize) ringCount++;

        final kS = 0.08, kM = 0.22, kF = 0.45;
        emaSlow += (a - emaSlow) * kS;
        emaMed += (a - emaMed) * kM;
        emaFast += (a - emaFast) * kF;

        final spike = (a - prevNorm).clamp(0.0, 1.0);
        onsetEnv = math.max(onsetEnv * 0.88, spike > 0.1 ? spike * 1.6 : onsetEnv * 0.75);
        prevNorm = a;

        final rmsInterval = 1e6 / _rmsHz;
        if (now - lastRmsUs >= rmsInterval) {
          lastRmsUs = now;
          final bands = _fftBands(ring, ringWrite, ringCount);
          final bass = (0.55 * emaSlow + 0.45 * bands.$1).clamp(0.0, 1.0);
          final mid = (0.45 * (emaMed - emaSlow * 0.5).clamp(0.0, 1.0) * 1.3 +
                  0.55 * bands.$2)
              .clamp(0.0, 1.0);
          final treble = (0.4 * (emaFast - emaMed).abs().clamp(0.0, 1.0) * 1.5 +
                  0.6 * bands.$3)
              .clamp(0.0, 1.0);
          final rms = emaSlow.clamp(0.0, 1.0);

          // Pitch may update on slower cadence; reuse hold between pitch ticks.
          final pitchInterval = 1e6 / _pitchHz;
          if (now - lastPitchUs >= pitchInterval) {
            lastPitchUs = now;
            final p = _estimatePitch(ring, ringWrite, ringCount, bands);
            pitchHold = pitchHold * 0.65 + p.$1 * 0.35;
            confidenceHold = pitchHold * 0.4 + p.$2 * 0.6;
          }

          emit(AudioFeatures(
            rms: rms,
            pitch: pitchHold.clamp(0.0, 1.0),
            bass: bass,
            mid: mid,
            treble: treble,
            onset: onsetEnv.clamp(0.0, 1.0),
            confidence: confidenceHold.clamp(0.0, 1.0),
          ));
        }
    }
  });
}

/// Tiny real-DFT energy in low / mid / high bins over amp ring (worker-only).
(double, double, double) _fftBands(List<double> ring, int write, int count) {
  if (count < 8) return (0.2, 0.25, 0.15);
  final n = count.clamp(8, _fftSize);
  var eLow = 0.0, eMid = 0.0, eHi = 0.0, eAll = 1e-9;
  // Analyze last n samples ending at write-1
  for (var k = 1; k < n ~/ 2; k++) {
    var re = 0.0, im = 0.0;
    for (var i = 0; i < n; i++) {
      final idx = (write - n + i + _fftSize) % _fftSize;
      final ang = -2 * math.pi * k * i / n;
      re += ring[idx] * math.cos(ang);
      im += ring[idx] * math.sin(ang);
    }
    final mag = math.sqrt(re * re + im * im) / n;
    eAll += mag;
    final frac = k / (n / 2);
    if (frac < 0.25) {
      eLow += mag;
    } else if (frac < 0.6) {
      eMid += mag;
    } else {
      eHi += mag;
    }
  }
  return (
    (eLow / eAll * 2).clamp(0.0, 1.0),
    (eMid / eAll * 2).clamp(0.0, 1.0),
    (eHi / eAll * 2).clamp(0.0, 1.0),
  );
}

(double, double) _estimatePitch(
  List<double> ring,
  int write,
  int count,
  (double, double, double) bands,
) {
  if (count < 16) {
    final sum = bands.$1 + bands.$2 + bands.$3 + 1e-4;
    return ((0.2 * bands.$1 + 0.5 * bands.$2 + 0.85 * bands.$3) / sum, 0.3);
  }
  // Autocorr peak on recent window → period proxy → normalized pitch.
  final n = math.min(count, 48);
  var bestLag = 4;
  var best = -1.0;
  for (var lag = 4; lag < n ~/ 2; lag++) {
    var corr = 0.0;
    for (var i = 0; i < n - lag; i++) {
      final a = ring[(write - n + i + _fftSize) % _fftSize];
      final b = ring[(write - n + i + lag + _fftSize) % _fftSize];
      corr += a * b;
    }
    if (corr > best) {
      best = corr;
      bestLag = lag;
    }
  }
  // Map lag to 0–1 (shorter lag → higher pitch)
  final pitch = (1.0 - (bestLag - 4) / (n / 2 - 4)).clamp(0.0, 1.0);
  final conf = (best / (n + 1e-6)).clamp(0.0, 1.0);
  final centroid = (0.15 * bands.$1 + 0.5 * bands.$2 + 0.85 * bands.$3) /
      (bands.$1 + bands.$2 + bands.$3 + 1e-4);
  return (pitch * 0.55 + centroid * 0.45, conf * 0.5 + 0.25);
}
