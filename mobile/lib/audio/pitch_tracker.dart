import 'dart:math' as math;
import 'dart:typed_data';

/// Continuous pitch control (0–1) from YIN-style fundamental estimation.
///
/// Not a tuner: prioritizes stable, monotonic low↔high mapping with
/// octave-jump correction, median denoise, and asymmetric EMA smoothing.
class PitchTracker {
  PitchTracker({this.sampleRate = 16000});

  final int sampleRate;

  static const minHz = 70.0;
  static const maxHz = 1200.0;
  static const confidenceFloor = 0.55;
  static const holdMs = 200.0;
  static const riseSec = 0.11; // ~80–150 ms
  static const fallSec = 0.22; // ~150–300 ms
  static const maxDeltaPerSec = 2.2; // visual slew limit on 0–1

  final List<double> _medianBuf = [];
  double _prevHz = 0;
  double _visualPitch = 0.45;
  double _confidenceSmooth = 0;
  double _holdRemainMs = 0;
  double _lastGoodPitch = 0.45;

  double get visualPitch => _visualPitch;
  double get confidence => _confidenceSmooth;

  void reset() {
    _medianBuf.clear();
    _prevHz = 0;
    _visualPitch = 0.45;
    _confidenceSmooth = 0;
    _holdRemainMs = 0;
    _lastGoodPitch = 0.45;
  }

  /// [pcm] mono float −1…1. Returns (pitchControl, confidence).
  (double, double) process({
    required Float64List pcm,
    required double rms,
    required double noiseGate,
    required double spectralCentroid01,
    required double dtSec,
  }) {
    final yin = _yin(pcm, sampleRate);
    var candHz = yin.$1;
    var conf = yin.$2;

    // Gate by level.
    if (rms < noiseGate) {
      conf = 0;
    }

    _confidenceSmooth = _ar(
      _confidenceSmooth,
      conf,
      0.08,
      0.18,
      dtSec,
    );

    double targetNorm;
    if (conf >= confidenceFloor && candHz > 0) {
      candHz = _correctOctaveJump(candHz, _prevHz > 0 ? _prevHz : candHz);
      _prevHz = candHz;
      final med = _medianPush(candHz);
      targetNorm = pitchToNormalized(med);
      _lastGoodPitch = targetNorm;
      _holdRemainMs = holdMs;
    } else if (_holdRemainMs > 0) {
      _holdRemainMs -= dtSec * 1000;
      targetNorm = _lastGoodPitch;
    } else {
      // No reliable F0 → follow spectral / timbre height proxy (amp fallback).
      final centroidNorm = spectralCentroid01.clamp(0.0, 1.0);
      final w = (_confidenceSmooth * 0.35).clamp(0.0, 1.0);
      targetNorm = w * _lastGoodPitch + (1 - w) * centroidNorm;
      // Only drift to neutral in true quiet — keep moving while sound is present.
      if (rms < noiseGate * 0.7) {
        targetNorm = _ar(targetNorm, 0.45, 0.55, 0.55, dtSec);
      } else {
        _lastGoodPitch = targetNorm;
      }
    }

    // Asymmetric EMA + slew limit.
    final rising = targetNorm > _visualPitch;
    final tau = rising ? riseSec : fallSec;
    var next = _ar(_visualPitch, targetNorm, tau, tau, dtSec);
    final maxStep = maxDeltaPerSec * dtSec;
    final delta = (next - _visualPitch).clamp(-maxStep, maxStep);
    _visualPitch = (_visualPitch + delta).clamp(0.0, 1.0);

    return (_visualPitch, _confidenceSmooth);
  }

  static double pitchToNormalized(double hz) {
    if (hz <= 0) return 0.45;
    final value = math.log(hz / minHz) / math.log(maxHz / minHz);
    return value.clamp(0.0, 1.0);
  }

  double _correctOctaveJump(double detected, double previous) {
    if (previous <= 0) return detected;
    var hz = detected;
    // Prefer candidate within ~1.5× of previous.
    for (var i = 0; i < 3; i++) {
      final half = hz * 0.5;
      final dbl = hz * 2.0;
      final err = (hz - previous).abs();
      final errHalf = (half - previous).abs();
      final errDbl = (dbl - previous).abs();
      if (half >= minHz && errHalf < err * 0.72 && errHalf < errDbl) {
        hz = half;
      } else if (dbl <= maxHz && errDbl < err * 0.72) {
        hz = dbl;
      } else {
        break;
      }
    }
    return hz.clamp(minHz, maxHz);
  }

  double _medianPush(double hz) {
    _medianBuf.add(hz);
    if (_medianBuf.length > 5) _medianBuf.removeAt(0);
    final sorted = List<double>.from(_medianBuf)..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// Cumulative mean normalized difference (YIN-lite).
  /// Returns (hz, confidence 0–1).
  static (double, double) _yin(Float64List x, int sr) {
    final n = x.length;
    if (n < 64) return (0.0, 0.0);

    final tauMin = (sr / maxHz).floor().clamp(2, n ~/ 4);
    final tauMax = (sr / minHz).floor().clamp(tauMin + 2, n ~/ 2);

    // Difference function d(τ)
    final d = Float64List(tauMax + 1);
    for (var tau = tauMin; tau <= tauMax; tau++) {
      var sum = 0.0;
      final lim = n - tau;
      for (var i = 0; i < lim; i++) {
        final diff = x[i] - x[i + tau];
        sum += diff * diff;
      }
      d[tau] = sum;
    }

    // Cumulative mean normalized difference
    final cmnd = Float64List(tauMax + 1);
    cmnd[0] = 1;
    var run = 0.0;
    for (var tau = 1; tau <= tauMax; tau++) {
      run += d[tau];
      cmnd[tau] = run > 1e-12 ? d[tau] * tau / run : 1.0;
    }

    const thresh = 0.15;
    var bestTau = -1;
    var bestVal = 1.0;
    for (var tau = tauMin; tau <= tauMax; tau++) {
      final v = cmnd[tau];
      if (v < thresh) {
        // Local minimum
        while (tau + 1 <= tauMax && cmnd[tau + 1] < cmnd[tau]) {
          tau++;
        }
        bestTau = tau;
        bestVal = cmnd[tau];
        break;
      }
      if (v < bestVal) {
        bestVal = v;
        bestTau = tau;
      }
    }

    if (bestTau < tauMin) return (0.0, 0.0);

    // Parabolic interpolation
    final x0 = bestTau > 0 ? cmnd[bestTau - 1] : cmnd[bestTau];
    final x1 = cmnd[bestTau];
    final x2 = bestTau + 1 <= tauMax ? cmnd[bestTau + 1] : cmnd[bestTau];
    final denom = 2 * (x0 - 2 * x1 + x2);
    var refined = bestTau.toDouble();
    if (denom.abs() > 1e-9) {
      refined = bestTau + (x0 - x2) / denom;
    }

    final hz = sr / refined;
    if (hz < minHz * 0.9 || hz > maxHz * 1.1) return (0.0, 0.0);
    final confidence = (1.0 - bestVal).clamp(0.0, 1.0);
    return (hz.clamp(minHz, maxHz), confidence);
  }

  static double _ar(
    double cur,
    double target,
    double attackSec,
    double releaseSec,
    double dt,
  ) {
    final tau = target > cur ? attackSec : releaseSec;
    final k = 1.0 - math.exp(-dt / tau.clamp(0.001, 2.0));
    return cur + (target - cur) * k;
  }
}

/// Append PCM16 mono samples into a growable float ring for YIN.
class PcmRing {
  PcmRing(this.capacity) : _buf = Float64List(capacity);

  final int capacity;
  final Float64List _buf;
  int _write = 0;
  int _count = 0;

  int get count => _count;

  void clear() {
    _write = 0;
    _count = 0;
  }

  void pushInt16Bytes(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final n = bytes.length ~/ 2;
    for (var i = 0; i < n; i++) {
      final s = bd.getInt16(i * 2, Endian.little) / 32768.0;
      _buf[_write] = s;
      _write = (_write + 1) % capacity;
      if (_count < capacity) _count++;
    }
  }

  /// Latest contiguous window (copies).
  Float64List latestWindow(int length) {
    final len = math.min(length, _count);
    final out = Float64List(len);
    for (var i = 0; i < len; i++) {
      final idx = (_write - len + i + capacity) % capacity;
      out[i] = _buf[idx];
    }
    return out;
  }

  double rmsWindow(int length) {
    final len = math.min(length, _count);
    if (len <= 0) return 0;
    var e2 = 0.0;
    for (var i = 0; i < len; i++) {
      final idx = (_write - len + i + capacity) % capacity;
      final v = _buf[idx];
      e2 += v * v;
    }
    return math.sqrt(e2 / len);
  }
}
