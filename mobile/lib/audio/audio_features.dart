/// Normalized audio descriptors consumed by the visual layer (UI thread).
/// Produced off-thread at ~25–30 Hz (RMS/bands) and ~15–25 Hz (pitch).
class AudioFeatures {
  const AudioFeatures({
    this.rms = 0.1,
    this.pitch = 0.45,
    this.bass = 0.2,
    this.mid = 0.25,
    this.treble = 0.15,
    this.onset = 0,
    this.confidence = 0.4,
  });

  final double rms;
  final double pitch;
  final double bass;
  final double mid;
  final double treble;
  final double onset;
  final double confidence;

  static const silent = AudioFeatures();

  AudioFeatures lerp(AudioFeatures o, double t) {
    double L(double a, double b) => a + (b - a) * t;
    return AudioFeatures(
      rms: L(rms, o.rms),
      pitch: L(pitch, o.pitch),
      bass: L(bass, o.bass),
      mid: L(mid, o.mid),
      treble: L(treble, o.treble),
      onset: L(onset, o.onset),
      confidence: L(confidence, o.confidence),
    );
  }

  Map<String, double> toMap() => {
        'rms': rms,
        'pitch': pitch,
        'bass': bass,
        'mid': mid,
        'treble': treble,
        'onset': onset,
        'confidence': confidence,
      };

  factory AudioFeatures.fromMap(Map<dynamic, dynamic> m) => AudioFeatures(
        rms: (m['rms'] as num?)?.toDouble() ?? 0.1,
        pitch: (m['pitch'] as num?)?.toDouble() ?? 0.45,
        bass: (m['bass'] as num?)?.toDouble() ?? 0.2,
        mid: (m['mid'] as num?)?.toDouble() ?? 0.25,
        treble: (m['treble'] as num?)?.toDouble() ?? 0.15,
        onset: (m['onset'] as num?)?.toDouble() ?? 0,
        confidence: (m['confidence'] as num?)?.toDouble() ?? 0.4,
      );
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
    bloom: true,
    particleCount: 8,
    resolutionScale: 1.0,
    targetFps: 60,
  );

  static const medium = VisualQualityProfile(
    tier: VisualQuality.medium,
    bloom: false,
    particleCount: 5,
    resolutionScale: 0.85,
    targetFps: 60,
  );

  static const low = VisualQualityProfile(
    tier: VisualQuality.low,
    bloom: false,
    particleCount: 2,
    resolutionScale: 0.65,
    targetFps: 45,
  );

  static const idle = VisualQualityProfile(
    tier: VisualQuality.medium,
    bloom: false,
    particleCount: 3,
    resolutionScale: 0.85,
    targetFps: 24,
  );

  static VisualQualityProfile forTier(VisualQuality t) => switch (t) {
        VisualQuality.high => high,
        VisualQuality.medium => medium,
        VisualQuality.low => low,
      };
}
