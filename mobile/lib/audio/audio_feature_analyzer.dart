import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'audio_features.dart';

/// Off-UI-thread audio analysis (PixMusic-style AGC / soft gate / multi-band).
///
/// Ingests mic amplitude (dBFS or 0–1) at ~20–50 ms. Builds DC-removed ring,
/// adaptive noise floor, fast-attack slow-release AGC, soft gate, multi-scale
/// envelopes, modulation-spectrum bins, flux & onset. UI only observes
/// [features] / [liveVolume].
class AudioFeatureAnalyzer {
  AudioFeatureAnalyzer._(this._worker, this._toWorker);

  final Isolate _worker;
  final SendPort _toWorker;
  final ValueNotifier<AudioFeatures> features =
      ValueNotifier(AudioFeatures.silent);
  /// Gated + AGC'd volume for fast visual coupling (~emit rate).
  final ValueNotifier<double> liveVolume = ValueNotifier(0.0);
  final ReceivePort _fromWorker = ReceivePort();
  StreamSubscription? _sub;
  bool _active = false;
  bool _disposed = false;
  /// Cap UI notifier updates (~25 Hz) even if isolate emits faster.
  static const _uiMinIntervalUs = 40000; // 25 Hz
  int _lastUiEmitUs = 0;
  Map? _pendingUiMsg;
  Timer? _uiFlushTimer;

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
      if (msg is! Map) return;
      analyzer._queueUi(msg);
    });
    toWorker.send({
      'cmd': 'init',
      'port': analyzer._fromWorker.sendPort,
    });
    return analyzer;
  }

  void _queueUi(Map msg) {
    if (_disposed) return;
    final now = DateTime.now().microsecondsSinceEpoch;
    if (now - _lastUiEmitUs >= _uiMinIntervalUs) {
      _publishUi(msg, now);
      return;
    }
    _pendingUiMsg = msg;
    _uiFlushTimer ??= Timer(
      Duration(microseconds: _uiMinIntervalUs - (now - _lastUiEmitUs)),
      () {
        _uiFlushTimer = null;
        final pending = _pendingUiMsg;
        _pendingUiMsg = null;
        if (pending != null && !_disposed) {
          _publishUi(pending, DateTime.now().microsecondsSinceEpoch);
        }
      },
    );
  }

  void _publishUi(Map msg, int nowUs) {
    _lastUiEmitUs = nowUs;
    final f = AudioFeatures.fromMap(msg);
    features.value = f;
    liveVolume.value = f.gatedRms.clamp(0.0, 1.0);
  }

  void pushAmplitude(double amp) {
    if (_disposed || !_active) return;
    _toWorker.send({
      'cmd': 'amp',
      'v': amp,
      't': DateTime.now().microsecondsSinceEpoch,
    });
  }

  void setActive(bool active) {
    _active = active;
    if (_disposed) return;
    _toWorker.send({'cmd': 'active', 'v': active});
    if (!active) {
      features.value = AudioFeatures.silent;
      liveVolume.value = 0;
    }
  }

  void dispose() {
    _disposed = true;
    _active = false;
    _uiFlushTimer?.cancel();
    _uiFlushTimer = null;
    _pendingUiMsg = null;
    _sub?.cancel();
    _fromWorker.close();
    features.dispose();
    liveVolume.dispose();
    _toWorker.send({'cmd': 'dispose'});
    _worker.kill(priority: Isolate.immediate);
  }
}

// ─── Worker isolate ─────────────────────────────────────────────────────────

const _emitHz = 28.0;
const _ringSize = 128;
const _specBins = AudioFeatures.spectrumBinCount;
const _minGain = 0.8;
const _maxGain = 10.0;

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _smoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Asymmetric EMA using time constants (seconds) → per-frame factor.
double _ar(double cur, double target, double attackSec, double releaseSec, double dt) {
  final tau = target > cur ? attackSec : releaseSec;
  final k = 1.0 - math.exp(-dt / tau.clamp(0.001, 2.0));
  return cur + (target - cur) * k;
}

double _normAmp(double v) {
  if (v <= 1.0 && v >= 0.0) return v;
  return ((v + 60) / 60).clamp(0.0, 1.0);
}

void _analyzerMain(SendPort ready) {
  final inbox = ReceivePort();
  ready.send(inbox.sendPort);

  SendPort? out;
  var active = false;

  final ring = Float64List(_ringSize);
  var ringWrite = 0;
  var ringCount = 0;
  var dcMean = 0.0;

  var trackedPeak = 0.12;
  var agcGain = 2.5;
  var noiseFloor = 0.025;
  var quietAccumUs = 0;
  var warmupUs = 0;
  const warmupTargetUs = 1500000; // 1.5s

  var emaFast = 0.0;
  var emaSlow = 0.04;
  var bassE = 0.12, lowMidE = 0.12, midE = 0.15, highMidE = 0.1, trebleE = 0.08;
  var onsetEnv = 0.0;
  var fluxHold = 0.0;
  var prevGated = 0.0;
  var zcrE = 0.2;
  var lastEmitUs = 0;
  var lastAmpUs = 0;

  final prevSpec = Float64List(_specBins);
  final workSpec = Float64List(_specBins);
  final hannScratch = Float64List(_ringSize);

  void emit(AudioFeatures f) => out?.send(f.toMap());

  void resetState() {
    ringWrite = 0;
    ringCount = 0;
    dcMean = 0;
    trackedPeak = 0.12;
    agcGain = 2.5;
    noiseFloor = 0.025;
    quietAccumUs = 0;
    warmupUs = 0;
    emaFast = 0;
    emaSlow = 0.04;
    bassE = lowMidE = midE = 0.12;
    highMidE = trebleE = 0.08;
    onsetEnv = 0;
    fluxHold = 0;
    prevGated = 0;
    for (var i = 0; i < _specBins; i++) {
      prevSpec[i] = 0;
    }
  }

  /// Modulation-spectrum DFT on amplitude ring (rhythm / speech cadence).
  /// Bins are remapped into bass…treble proxies for local visual drive.
  void computeSpectrum() {
    final n = ringCount.clamp(16, _ringSize);
    // Hann window + DC remove
    var mean = 0.0;
    for (var i = 0; i < n; i++) {
      final idx = (ringWrite - n + i + _ringSize) % _ringSize;
      mean += ring[idx];
    }
    mean /= n;
    for (var i = 0; i < n; i++) {
      final idx = (ringWrite - n + i + _ringSize) % _ringSize;
      final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
      hannScratch[i] = (ring[idx] - mean) * w;
    }

    final half = n ~/ 2;
    // Pack energy into _specBins with logarithmic k spacing
    for (var b = 0; b < _specBins; b++) {
      final t0 = b / _specBins;
      final t1 = (b + 1) / _specBins;
      // log-ish: emphasize lower modulation bins
      final k0 = (math.pow(half - 1, t0).toDouble()).clamp(1.0, half - 1.0);
      final k1 = (math.pow(half - 1, t1).toDouble()).clamp(k0 + 0.5, half - 0.5);
      var e = 0.0;
      var wSum = 0.0;
      final kStart = k0.floor();
      final kEnd = k1.ceil().clamp(kStart + 1, half);
      for (var k = kStart; k < kEnd; k++) {
        var re = 0.0, im = 0.0;
        for (var i = 0; i < n; i++) {
          final ang = -2 * math.pi * k * i / n;
          re += hannScratch[i] * math.cos(ang);
          im += hannScratch[i] * math.sin(ang);
        }
        final mag = math.sqrt(re * re + im * im) / n;
        e += mag;
        wSum += 1;
      }
      workSpec[b] = wSum > 0 ? e / wSum : 0;
    }

    // Normalize relative to peak bin
    var peak = 1e-9;
    for (var i = 0; i < _specBins; i++) {
      if (workSpec[i] > peak) peak = workSpec[i];
    }
    for (var i = 0; i < _specBins; i++) {
      workSpec[i] = (workSpec[i] / peak).clamp(0.0, 1.0);
    }
  }

  inbox.listen((msg) {
    if (msg is! Map) return;
    switch (msg['cmd']) {
      case 'init':
        out = msg['port'] as SendPort;
      case 'active':
        active = msg['v'] == true;
        if (!active) {
          emit(AudioFeatures.silent);
          resetState();
        }
      case 'dispose':
        inbox.close();
      case 'amp':
        if (!active || out == null) return;
        final now = msg['t'] as int? ?? DateTime.now().microsecondsSinceEpoch;
        final dt = lastAmpUs == 0
            ? 1 / 50
            : ((now - lastAmpUs) / 1e6).clamp(0.008, 0.08);
        lastAmpUs = now;

        final raw = _normAmp((msg['v'] as num).toDouble());

        // Running DC estimate + ring
        dcMean = _lerp(dcMean, raw, 0.04);
        final sample = raw;
        ring[ringWrite] = sample;
        ringWrite = (ringWrite + 1) % _ringSize;
        if (ringCount < _ringSize) ringCount++;

        // Instantaneous RMS over short window
        final win = math.min(ringCount, 24);
        var e2 = 0.0;
        for (var i = 0; i < win; i++) {
          final v = ring[(ringWrite - 1 - i + _ringSize) % _ringSize];
          e2 += v * v;
        }
        final instRms = math.sqrt(e2 / win);

        // Warmup: seed noise floor from quiet start
        if (warmupUs < warmupTargetUs) {
          warmupUs += (dt * 1e6).round();
          noiseFloor = _lerp(noiseFloor, instRms, 0.08);
        }

        // Fast-attack / slow-release peak tracker (PixMusic SPHERE AGC)
        if (instRms > trackedPeak) {
          trackedPeak = trackedPeak * 0.5 + instRms * 0.5;
        } else {
          trackedPeak = trackedPeak * 0.995 + instRms * 0.005;
        }
        final denom = math.max(noiseFloor * 1.5, trackedPeak);
        // Map PixMusic-style gain (≈230/peak) into our 0–1 feature space.
        final targetGain =
            ((230.0 / math.max(denom * 255.0, 1.0)) * 0.55)
                .clamp(_minGain, _maxGain);
        agcGain = _lerp(agcGain, targetGain, 0.18);

        final boosted = (instRms * agcGain).clamp(0.0, 1.5);

        // Soft gate — never hard-zero light speech
        final gate = _smoothstep(noiseFloor, noiseFloor * 2.5, boosted);
        final gated = (boosted * gate).clamp(0.0, 1.0);

        // Adaptive noise floor only when truly quiet
        final nearFloor = instRms < noiseFloor * 1.8 + 0.01;
        final lowFlux = fluxHold < 0.12;
        final noOnset = onsetEnv < 0.15;
        if (nearFloor && lowFlux && noOnset && warmupUs >= warmupTargetUs) {
          quietAccumUs += (dt * 1e6).round();
          if (quietAccumUs > 400000) {
            noiseFloor = _lerp(noiseFloor, instRms, 0.015);
          }
        } else {
          quietAccumUs = 0;
        }
        noiseFloor = noiseFloor.clamp(0.004, 0.12);

        // Multi-scale envelopes on gated energy
        emaFast = _ar(emaFast, gated, 0.028, 0.14, dt);
        emaSlow = _ar(emaSlow, gated, 0.18, 0.65, dt);

        // Band proxies from multi-rate differentials + spectrum (below)
        final dFast = (gated - prevGated).clamp(-1.0, 1.0);
        prevGated = gated;

        // Onset: rapid rise
        final spike = dFast.clamp(0.0, 1.0);
        if (spike > 0.08 && gated > noiseFloor * 3) {
          onsetEnv = math.max(onsetEnv, (spike * 2.2).clamp(0.0, 1.0));
        } else {
          onsetEnv = _ar(onsetEnv, 0, 0.05, 0.28, dt);
        }

        // ZCR of AC component (noisiness / fricatives)
        var crossings = 0;
        final zWin = math.min(ringCount, 32);
        for (var i = 1; i < zWin; i++) {
          final a = ring[(ringWrite - i + _ringSize) % _ringSize] - dcMean;
          final b = ring[(ringWrite - i - 1 + _ringSize) % _ringSize] - dcMean;
          if ((a >= 0 && b < 0) || (a < 0 && b >= 0)) crossings++;
        }
        final zcr = (crossings / math.max(1, zWin - 1)).clamp(0.0, 1.0);
        zcrE = _ar(zcrE, zcr, 0.05, 0.12, dt);

        final emitInterval = 1e6 / _emitHz;
        if (now - lastEmitUs < emitInterval) return;
        lastEmitUs = now;

        computeSpectrum();

        // Spectral flux
        var flux = 0.0;
        for (var i = 0; i < _specBins; i++) {
          final d = workSpec[i] - prevSpec[i];
          if (d > 0) flux += d;
          prevSpec[i] = workSpec[i];
        }
        flux = (flux / _specBins * 3.5).clamp(0.0, 1.0);
        fluxHold = math.max(fluxHold * 0.82, flux);
        fluxHold = _ar(fluxHold, flux, 0.04, 0.22, dt);

        // Map spectrum thirds + envelope diffs → named bands
        double bandAvg(int a, int b) {
          var s = 0.0;
          final n = math.max(1, b - a);
          for (var i = a; i < b; i++) {
            s += workSpec[i.clamp(0, _specBins - 1)];
          }
          return s / n;
        }

        final sBass = bandAvg(0, 16);
        final sLowMid = bandAvg(16, 36);
        final sMid = bandAvg(36, 64);
        final sHighMid = bandAvg(64, 96);
        final sTreble = bandAvg(96, _specBins);

        // Blend spectrum shape with envelope dynamics (speech still drives mid)
        final bassT =
            (0.55 * sBass + 0.35 * emaSlow + 0.15 * (1 - zcrE)).clamp(0.0, 1.0);
        final lowMidT =
            (0.50 * sLowMid + 0.35 * emaSlow + 0.20 * emaFast).clamp(0.0, 1.0);
        final midT =
            (0.45 * sMid + 0.40 * emaFast + 0.20 * fluxHold).clamp(0.0, 1.0);
        final highMidT =
            (0.50 * sHighMid + 0.30 * emaFast + 0.25 * zcrE).clamp(0.0, 1.0);
        final trebleT =
            (0.45 * sTreble + 0.35 * zcrE + 0.25 * spike.abs()).clamp(0.0, 1.0);

        bassE = _ar(bassE, bassT * gated, 0.04, 0.22, dt);
        lowMidE = _ar(lowMidE, lowMidT * gated, 0.035, 0.16, dt);
        midE = _ar(midE, midT * gated, 0.028, 0.12, dt);
        highMidE = _ar(highMidE, highMidT * gated, 0.025, 0.10, dt);
        trebleE = _ar(trebleE, trebleT * gated, 0.022, 0.09, dt);

        // Centroid from band weights
        final wSum = bassE + lowMidE + midE + highMidE + trebleE + 1e-4;
        final centroid = (0.08 * bassE +
                0.25 * lowMidE +
                0.45 * midE +
                0.70 * highMidE +
                0.92 * trebleE) /
            wSum;

        // Perceptual lift of gated for quiet speech (after AGC already helped)
        final perceptual = math
            .pow(gated.clamp(0.0, 1.0), 0.62)
            .toDouble()
            .clamp(0.0, 1.0);

        emit(AudioFeatures(
          rms: instRms.clamp(0.0, 1.0),
          gatedRms: perceptual,
          fastEnvelope: emaFast.clamp(0.0, 1.0),
          slowEnvelope: emaSlow.clamp(0.0, 1.0),
          bass: bassE.clamp(0.0, 1.0),
          lowMid: lowMidE.clamp(0.0, 1.0),
          mid: midE.clamp(0.0, 1.0),
          highMid: highMidE.clamp(0.0, 1.0),
          treble: trebleE.clamp(0.0, 1.0),
          spectralCentroid: centroid.clamp(0.0, 1.0),
          spectralFlux: fluxHold.clamp(0.0, 1.0),
          onset: onsetEnv.clamp(0.0, 1.0),
          zeroCrossingRate: zcrE.clamp(0.0, 1.0),
          pitch: centroid.clamp(0.0, 1.0),
          confidence: gate.clamp(0.0, 1.0),
          agcGain: agcGain,
          noiseFloor: noiseFloor,
          trackedPeak: trackedPeak,
          spectrum: List<double>.generate(_specBins, (i) => workSpec[i]),
        ));
    }
  });
}
