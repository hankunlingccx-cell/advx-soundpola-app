import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/audio_features.dart';

/// Deterministic renderer version — bump when bake algorithm changes.
/// Old packages keep their stored frames and this string for provenance.
const kSoundVisualRendererVersion = 'soundpola_kaleido_linear_v2';

/// Default bake settings (Collection / Memory playback).
const kVisualBakeFps = 12;
const kVisualBakeSize = 512;
const kVisualBakeJpegQuality = 80;
const kVisualBakeHighFps = 15;
const kVisualBakeHighSize = 720;
const kVisualBakeHighJpegQuality = 85;

/// Soft cap for recording / import / MJPEG bake budget (seconds).
const kMaxRecordingDurationSec = 30;

enum VisualBakeStatus {
  /// No package / legacy entry without bake.
  none,
  /// Features being captured with audio.
  recording,
  /// Offline re-render of JPEG frames.
  processingVisual,
  /// Writing idx / manifest / cover.
  indexing,
  /// Indexed MJPEG ready for playback.
  ready,
  /// Bake failed; audio + features retained for retry.
  failed,
}

/// One AudioDrive sample on the audio timeline.
class AudioFeatureSample {
  const AudioFeatureSample({
    required this.timeMs,
    required this.features,
  });

  final int timeMs;
  final AudioFeatures features;
}

/// In-memory / on-disk AudioDrive time series for deterministic bake.
class AudioFeatureTimeline {
  AudioFeatureTimeline({List<AudioFeatureSample>? samples})
      : samples = samples ?? <AudioFeatureSample>[];

  final List<AudioFeatureSample> samples;

  bool get isEmpty => samples.isEmpty;
  int get length => samples.length;
  int get durationMs => samples.isEmpty ? 0 : samples.last.timeMs;

  void clear() => samples.clear();

  void add(int timeMs, AudioFeatures f) {
    if (samples.isNotEmpty && timeMs < samples.last.timeMs) return;
    // Downsample: keep ~40 Hz max
    if (samples.isNotEmpty && timeMs - samples.last.timeMs < 24) {
      samples[samples.length - 1] =
          AudioFeatureSample(timeMs: timeMs, features: f);
      return;
    }
    samples.add(AudioFeatureSample(timeMs: timeMs, features: f));
  }

  /// Linear interpolate nearest neighbors at [timeMs].
  AudioFeatures sampleAt(int timeMs) {
    if (samples.isEmpty) return AudioFeatures.silent;
    if (timeMs <= samples.first.timeMs) return samples.first.features;
    if (timeMs >= samples.last.timeMs) return samples.last.features;
    var lo = 0;
    var hi = samples.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (samples[mid].timeMs <= timeMs) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = samples[lo];
    final b = samples[hi];
    final span = math.max(1, b.timeMs - a.timeMs);
    final t = ((timeMs - a.timeMs) / span).clamp(0.0, 1.0);
    return a.features.lerp(b.features, t);
  }

  /// SPAF binary: magic + version + bins + count + samples.
  /// v1: 13 floats (+ spectrum). v2: + pitchControl + confidence.
  Uint8List encode() {
    const floatsPer = 15;
    final bins = AudioFeatures.spectrumBinCount;
    final count = samples.length;
    final bytes = ByteData(
      4 + 2 + 2 + 4 + count * (4 + (floatsPer + bins) * 4),
    );
    var o = 0;
    bytes.setUint8(o++, 0x53); // S
    bytes.setUint8(o++, 0x50); // P
    bytes.setUint8(o++, 0x41); // A
    bytes.setUint8(o++, 0x46); // F
    bytes.setUint16(o, 2, Endian.little);
    o += 2;
    bytes.setUint16(o, bins, Endian.little);
    o += 2;
    bytes.setUint32(o, count, Endian.little);
    o += 4;
    for (final s in samples) {
      final f = s.features;
      bytes.setUint32(o, s.timeMs, Endian.little);
      o += 4;
      void put(double v) {
        bytes.setFloat32(o, v, Endian.little);
        o += 4;
      }

      put(f.rms);
      put(f.gatedRms);
      put(f.fastEnvelope);
      put(f.slowEnvelope);
      put(f.bass);
      put(f.lowMid);
      put(f.mid);
      put(f.highMid);
      put(f.treble);
      put(f.spectralCentroid);
      put(f.spectralFlux);
      put(f.onset);
      put(f.zeroCrossingRate);
      put(f.pitch);
      put(f.confidence);
      for (var i = 0; i < bins; i++) {
        put(i < f.spectrum.length ? f.spectrum[i] : 0);
      }
    }
    return bytes.buffer.asUint8List(0, o);
  }

  static AudioFeatureTimeline decode(Uint8List data) {
    final bytes = ByteData.sublistView(data);
    if (data.length < 12 ||
        bytes.getUint8(0) != 0x53 ||
        bytes.getUint8(1) != 0x50 ||
        bytes.getUint8(2) != 0x41 ||
        bytes.getUint8(3) != 0x46) {
      throw FormatException('Invalid audio_features.bin');
    }
    var o = 4;
    final version = bytes.getUint16(o, Endian.little);
    o += 2;
    if (version != 1 && version != 2) {
      throw FormatException('Unsupported features version $version');
    }
    final bins = bytes.getUint16(o, Endian.little);
    o += 2;
    final count = bytes.getUint32(o, Endian.little);
    o += 4;
    final out = AudioFeatureTimeline();
    for (var i = 0; i < count; i++) {
      final timeMs = bytes.getUint32(o, Endian.little);
      o += 4;
      double take() {
        final v = bytes.getFloat32(o, Endian.little);
        o += 4;
        return v;
      }

      final rms = take();
      final gated = take();
      final fast = take();
      final slow = take();
      final bass = take();
      final lowMid = take();
      final mid = take();
      final highMid = take();
      final treble = take();
      final centroid = take();
      final flux = take();
      final onset = take();
      final zcr = take();
      final pitch = version >= 2 ? take() : 0.45;
      final confidence = version >= 2 ? take() : 0.0;
      final spec = List<double>.generate(bins, (_) => take());
      out.samples.add(
        AudioFeatureSample(
          timeMs: timeMs,
          features: AudioFeatures(
            rms: rms,
            gatedRms: gated,
            fastEnvelope: fast,
            slowEnvelope: slow,
            bass: bass,
            lowMid: lowMid,
            mid: mid,
            highMid: highMid,
            treble: treble,
            spectralCentroid: centroid,
            spectralFlux: flux,
            onset: onset,
            zeroCrossingRate: zcr,
            pitch: pitch,
            confidence: confidence,
            spectrum: spec,
          ),
        ),
      );
    }
    return out;
  }
}
