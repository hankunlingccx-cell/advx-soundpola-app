import 'dart:typed_data';

/// Normalized audio descriptors for the visual layer (UI thread).
///
/// [pitch] is a continuous **pitchControl** in 0–1 (log-Hz mapped), not a
/// note name. Prefer stable low↔high correspondence over tuner accuracy.
class AudioFeatures {
  const AudioFeatures({
    this.rms = 0,
    this.gatedRms = 0,
    this.fastEnvelope = 0,
    this.slowEnvelope = 0,
    this.bass = 0.15,
    this.lowMid = 0.15,
    this.mid = 0.2,
    this.highMid = 0.12,
    this.treble = 0.1,
    this.spectralCentroid = 0.35,
    this.spectralFlux = 0,
    this.onset = 0,
    this.zeroCrossingRate = 0.2,
    this.pitch = 0.45,
    this.confidence = 0,
    this.agcGain = 1,
    this.noiseFloor = 0.02,
    this.trackedPeak = 0.1,
    this.spectrum = const <double>[],
  });

  /// Raw normalized RMS before AGC (diagnostics).
  final double rms;
  /// Soft-gated, AGC'd energy used for visuals.
  final double gatedRms;
  final double fastEnvelope;
  final double slowEnvelope;
  final double bass;
  final double lowMid;
  final double mid;
  final double highMid;
  final double treble;
  final double spectralCentroid;
  final double spectralFlux;
  final double onset;
  final double zeroCrossingRate;

  /// Continuous pitch control 0–1 (low→high). Alias: pitchControl.
  final double pitch;
  double get pitchControl => pitch;

  /// Smoothed YIN / F0 confidence 0–1.
  final double confidence;
  final double agcGain;
  final double noiseFloor;
  final double trackedPeak;

  /// Compact 0–1 spectrum bins (log-ish), length [spectrumBinCount].
  final List<double> spectrum;

  /// Frequency bin count for sphere mapping (PixMusic-style density).
  static const spectrumBinCount = 128;
  static const silent = AudioFeatures();

  double sampleSpectrumLog(double u) {
    if (spectrum.isEmpty) {
      return (bass * (1 - u) + mid * 0.6 + treble * u).clamp(0.0, 1.0);
    }
    final n = spectrum.length;
    final x = u.clamp(0.0, 1.0) * (n - 1);
    final i0 = x.floor().clamp(0, n - 1);
    final i1 = (i0 + 1).clamp(0, n - 1);
    final f = x - i0;
    return (spectrum[i0] * (1 - f) + spectrum[i1] * f).clamp(0.0, 1.0);
  }

  AudioFeatures lerp(AudioFeatures o, double t) {
    double L(double a, double b) => a + (b - a) * t;
    List<double> ls;
    if (spectrum.isEmpty && o.spectrum.isEmpty) {
      ls = const [];
    } else {
      final a = spectrum.isEmpty
          ? List<double>.filled(spectrumBinCount, 0)
          : spectrum;
      final b = o.spectrum.isEmpty
          ? List<double>.filled(spectrumBinCount, 0)
          : o.spectrum;
      final n = a.length < b.length ? a.length : b.length;
      ls = List<double>.generate(n, (i) => L(a[i], b[i]));
    }
    return AudioFeatures(
      rms: L(rms, o.rms),
      gatedRms: L(gatedRms, o.gatedRms),
      fastEnvelope: L(fastEnvelope, o.fastEnvelope),
      slowEnvelope: L(slowEnvelope, o.slowEnvelope),
      bass: L(bass, o.bass),
      lowMid: L(lowMid, o.lowMid),
      mid: L(mid, o.mid),
      highMid: L(highMid, o.highMid),
      treble: L(treble, o.treble),
      spectralCentroid: L(spectralCentroid, o.spectralCentroid),
      spectralFlux: L(spectralFlux, o.spectralFlux),
      onset: L(onset, o.onset),
      zeroCrossingRate: L(zeroCrossingRate, o.zeroCrossingRate),
      pitch: L(pitch, o.pitch),
      confidence: L(confidence, o.confidence),
      agcGain: L(agcGain, o.agcGain),
      noiseFloor: L(noiseFloor, o.noiseFloor),
      trackedPeak: L(trackedPeak, o.trackedPeak),
      spectrum: ls,
    );
  }

  Map<String, dynamic> toMap() => {
        'rms': rms,
        'gatedRms': gatedRms,
        'fastEnvelope': fastEnvelope,
        'slowEnvelope': slowEnvelope,
        'bass': bass,
        'lowMid': lowMid,
        'mid': mid,
        'highMid': highMid,
        'treble': treble,
        'spectralCentroid': spectralCentroid,
        'spectralFlux': spectralFlux,
        'onset': onset,
        'zeroCrossingRate': zeroCrossingRate,
        'pitch': pitch,
        'confidence': confidence,
        'agcGain': agcGain,
        'noiseFloor': noiseFloor,
        'trackedPeak': trackedPeak,
        'spectrum': spectrum,
      };

  factory AudioFeatures.fromMap(Map<dynamic, dynamic> m) {
    final rawSpec = m['spectrum'];
    List<double> spec = const [];
    if (rawSpec is Float32List) {
      spec = rawSpec.toList(growable: false);
    } else if (rawSpec is List) {
      spec = rawSpec.map((e) => (e as num).toDouble()).toList(growable: false);
    }
    return AudioFeatures(
      rms: (m['rms'] as num?)?.toDouble() ?? 0,
      gatedRms: (m['gatedRms'] as num?)?.toDouble() ??
          (m['rms'] as num?)?.toDouble() ??
          0,
      fastEnvelope: (m['fastEnvelope'] as num?)?.toDouble() ?? 0,
      slowEnvelope: (m['slowEnvelope'] as num?)?.toDouble() ?? 0,
      bass: (m['bass'] as num?)?.toDouble() ?? 0.15,
      lowMid: (m['lowMid'] as num?)?.toDouble() ?? 0.15,
      mid: (m['mid'] as num?)?.toDouble() ?? 0.2,
      highMid: (m['highMid'] as num?)?.toDouble() ?? 0.12,
      treble: (m['treble'] as num?)?.toDouble() ?? 0.1,
      spectralCentroid: (m['spectralCentroid'] as num?)?.toDouble() ?? 0.35,
      spectralFlux: (m['spectralFlux'] as num?)?.toDouble() ?? 0,
      onset: (m['onset'] as num?)?.toDouble() ?? 0,
      zeroCrossingRate: (m['zeroCrossingRate'] as num?)?.toDouble() ?? 0.2,
      pitch: (m['pitch'] as num?)?.toDouble() ?? 0.45,
      confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
      agcGain: (m['agcGain'] as num?)?.toDouble() ?? 1,
      noiseFloor: (m['noiseFloor'] as num?)?.toDouble() ?? 0.02,
      trackedPeak: (m['trackedPeak'] as num?)?.toDouble() ?? 0.1,
      spectrum: spec,
    );
  }
}

enum VisualQuality { high, medium, low }

class VisualQualityProfile {
  const VisualQualityProfile({
    required this.tier,
    required this.bloom,
    required this.particleCount,
    required this.resolutionScale,
    required this.targetFps,
  });

  final VisualQuality tier;
  final bool bloom;
  final int particleCount;
  final double resolutionScale;
  final double targetFps;

  static const high = VisualQualityProfile(
    tier: VisualQuality.high,
    bloom: false,
    particleCount: 480,
    resolutionScale: 1.0,
    targetFps: 48,
  );

  static const medium = VisualQualityProfile(
    tier: VisualQuality.medium,
    bloom: false,
    particleCount: 320,
    resolutionScale: 1.0,
    targetFps: 36,
  );

  static const low = VisualQualityProfile(
    tier: VisualQuality.low,
    bloom: false,
    particleCount: 180,
    resolutionScale: 0.9,
    targetFps: 24,
  );

  /// Frozen / list thumbnails — never drives a live ticker by default.
  static const idle = VisualQualityProfile(
    tier: VisualQuality.low,
    bloom: false,
    particleCount: 120,
    resolutionScale: 0.85,
    targetFps: 20,
  );

  static VisualQualityProfile forTier(VisualQuality t) => switch (t) {
        VisualQuality.high => high,
        VisualQuality.medium => medium,
        VisualQuality.low => low,
      };
}
