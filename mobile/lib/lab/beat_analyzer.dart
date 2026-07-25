import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../visual/audio_feature_timeline.dart';
import 'beat_models.dart';

/// Local beat analysis. Prefers AudioDrive timeline (spectral flux / onset / RMS);
/// optionally reads PCM from WAV for a true spectral-flux pass.
class BeatAnalyzer {
  BeatAnalyzer._();

  static const generatorHint = 'local_spectral_flux_v1';

  static Future<FeatureSummary> analyze({
    required String sourceSoundId,
    required int durationMs,
    String? audioPath,
    String? featuresPath,
    AudioFeatureTimeline? timeline,
    BeatStyle style = BeatStyle.minimal,
    BeatDensity density = BeatDensity.balanced,
  }) async {
    AudioFeatureTimeline? tl = timeline;
    if (tl == null && featuresPath != null) {
      final f = File(featuresPath);
      if (await f.exists()) {
        try {
          tl = AudioFeatureTimeline.decode(await f.readAsBytes());
        } catch (_) {}
      }
    }

    List<double>? pcm;
    int sampleRate = 22050;
    if (audioPath != null && audioPath.toLowerCase().endsWith('.wav')) {
      final decoded = await _tryDecodeWav(audioPath);
      if (decoded != null) {
        pcm = decoded.$1;
        sampleRate = decoded.$2;
      }
    }

    if (pcm != null && pcm.isNotEmpty) {
      return _fromPcm(
        pcm: pcm,
        sampleRate: sampleRate,
        sourceSoundId: sourceSoundId,
        style: style,
        density: density,
      );
    }

    if (tl != null && tl.samples.isNotEmpty) {
      return _fromTimeline(
        tl,
        sourceSoundId: sourceSoundId,
        durationMs: durationMs > 0 ? durationMs : tl.durationMs,
        style: style,
        density: density,
      );
    }

    // Fallback: empty-ish grid so BeatPlanner still runs deterministically.
    final dur = durationMs.clamp(1000, 180000);
    final bpm = 90.0;
    final step = (60000 / bpm).round();
    final grid = <int>[];
    for (var t = 0; t < dur; t += step) {
      grid.add(t);
    }
    return FeatureSummary(
      durationMs: dur,
      estimatedBpm: bpm,
      onsetsMs: const [],
      energySegments: [
        EnergySegment(startMs: 0, endMs: dur, energy: 0.4),
      ],
      silenceRanges: const [],
      requestedStyle: style.name,
      requestedDensity: density.name,
      beatGridMs: grid,
      candidateBeatMs: grid.where((t) => t % (step * 2) == 0).toList(),
      sourceSoundId: sourceSoundId,
    );
  }

  static FeatureSummary _fromTimeline(
    AudioFeatureTimeline tl, {
    required String sourceSoundId,
    required int durationMs,
    required BeatStyle style,
    required BeatDensity density,
  }) {
    final samples = tl.samples;
    final dur = math.max(durationMs, tl.durationMs);

    // Spectral-flux / onset peaks → onset list
    final fluxSeries = <({int t, double v})>[];
    for (final s in samples) {
      final v = math.max(s.features.spectralFlux, s.features.onset);
      fluxSeries.add((t: s.timeMs, v: v));
    }
    final onsets = _peakPick(fluxSeries, minGapMs: 90, threshold: 0.28);

    final bpm = _estimateBpmFromOnsets(onsets, dur);
    final grid = _buildBeatGrid(bpm, dur, onsets);
    final energy = _energySegmentsFromTimeline(samples, dur);
    final silence = _silenceFromTimeline(samples, dur);
    final candidates = _filterCandidates(
      onsets: onsets,
      grid: grid,
      silence: silence,
      energy: energy,
    );

    return FeatureSummary(
      durationMs: dur,
      estimatedBpm: bpm,
      onsetsMs: onsets,
      energySegments: energy,
      silenceRanges: silence,
      requestedStyle: style.name,
      requestedDensity: density.name,
      beatGridMs: grid,
      candidateBeatMs: candidates,
      sourceSoundId: sourceSoundId,
    );
  }

  static FeatureSummary _fromPcm({
    required List<double> pcm,
    required int sampleRate,
    required String sourceSoundId,
    required BeatStyle style,
    required BeatDensity density,
  }) {
    final hop = math.max(1, sampleRate ~/ 100); // ~10 ms
    final win = hop * 4;
    final flux = <({int t, double v})>[];
    final rms = <({int t, double v})>[];
    List<double>? prevMag;

    for (var i = 0; i + win < pcm.length; i += hop) {
      final frame = pcm.sublist(i, i + win);
      final mag = _bandMags(frame);
      double f = 0;
      if (prevMag != null) {
        for (var b = 0; b < mag.length; b++) {
          final d = mag[b] - prevMag[b];
          if (d > 0) f += d;
        }
      }
      prevMag = mag;
      var e = 0.0;
      for (final s in frame) {
        e += s * s;
      }
      e = math.sqrt(e / frame.length);
      final tMs = ((i / sampleRate) * 1000).round();
      flux.add((t: tMs, v: f));
      rms.add((t: tMs, v: e));
    }

    // Normalize flux
    var maxF = 1e-9;
    for (final x in flux) {
      if (x.v > maxF) maxF = x.v;
    }
    final normFlux = [
      for (final x in flux) (t: x.t, v: (x.v / maxF).clamp(0.0, 1.0)),
    ];
    var maxR = 1e-9;
    for (final x in rms) {
      if (x.v > maxR) maxR = x.v;
    }
    final normRms = [
      for (final x in rms) (t: x.t, v: (x.v / maxR).clamp(0.0, 1.0)),
    ];

    final dur = ((pcm.length / sampleRate) * 1000).round();
    final onsets = _peakPick(normFlux, minGapMs: 80, threshold: 0.22);
    final bpm = _estimateBpmFromOnsets(onsets, dur);
    final grid = _buildBeatGrid(bpm, dur, onsets);
    final energy = _energySegmentsFromSeries(normRms, dur);
    final silence = _silenceFromSeries(normRms, dur);
    final candidates = _filterCandidates(
      onsets: onsets,
      grid: grid,
      silence: silence,
      energy: energy,
    );

    return FeatureSummary(
      durationMs: dur,
      estimatedBpm: bpm,
      onsetsMs: onsets,
      energySegments: energy,
      silenceRanges: silence,
      requestedStyle: style.name,
      requestedDensity: density.name,
      beatGridMs: grid,
      candidateBeatMs: candidates,
      sourceSoundId: sourceSoundId,
    );
  }

  static List<double> _bandMags(List<double> frame) {
    // Lightweight pseudo-spectrum: 8 rectangular bands via decimated energy.
    const bands = 8;
    final out = List<double>.filled(bands, 0);
    final n = frame.length;
    for (var b = 0; b < bands; b++) {
      final start = (b * n) ~/ bands;
      final end = ((b + 1) * n) ~/ bands;
      var e = 0.0;
      for (var i = start; i < end; i++) {
        e += frame[i].abs();
      }
      out[b] = e / math.max(1, end - start);
    }
    return out;
  }

  static List<int> _peakPick(
    List<({int t, double v})> series, {
    required int minGapMs,
    required double threshold,
  }) {
    if (series.isEmpty) return const [];
    final mean = series.map((e) => e.v).reduce((a, b) => a + b) / series.length;
    final thr = math.max(threshold, mean * 1.35);
    final peaks = <int>[];
    for (var i = 1; i < series.length - 1; i++) {
      final cur = series[i];
      if (cur.v < thr) continue;
      if (cur.v < series[i - 1].v || cur.v < series[i + 1].v) continue;
      if (peaks.isNotEmpty && cur.t - peaks.last < minGapMs) {
        final prevPeak = series.where((s) => s.t == peaks.last);
        final prevV = prevPeak.isEmpty ? 0.0 : prevPeak.first.v;
        if (cur.v > prevV) {
          peaks[peaks.length - 1] = cur.t;
        }
        continue;
      }
      peaks.add(cur.t);
    }
    return peaks;
  }

  static double _estimateBpmFromOnsets(List<int> onsets, int durationMs) {
    if (onsets.length < 3) {
      // Autocorr-ish fallback on duration → mid tempo
      return 92.0;
    }
    final intervals = <int>[];
    for (var i = 1; i < onsets.length; i++) {
      final d = onsets[i] - onsets[i - 1];
      if (d >= 200 && d <= 1500) intervals.add(d);
    }
    if (intervals.isEmpty) return 92.0;

    // Autocorrelation on interval histogram (IOI)
    final hist = <int, int>{};
    for (final d in intervals) {
      final bin = (d / 10).round() * 10;
      hist[bin] = (hist[bin] ?? 0) + 1;
    }
    var bestBin = 652; // ~92 bpm
    var bestCount = 0;
    hist.forEach((bin, count) {
      if (count > bestCount) {
        bestCount = count;
        bestBin = bin;
      }
    });

    var bpm = 60000.0 / bestBin;
    // Fold into musical range
    while (bpm < 70) {
      bpm *= 2;
    }
    while (bpm > 160) {
      bpm /= 2;
    }
    return double.parse(bpm.toStringAsFixed(1));
  }

  static List<int> _buildBeatGrid(double bpm, int durationMs, List<int> onsets) {
    final step = math.max(1, (60000 / bpm).round());
    var phase = 0;
    if (onsets.isNotEmpty) {
      // Snap phase to first strong onset modulo step
      phase = onsets.first % step;
    }
    final grid = <int>[];
    for (var t = phase; t < durationMs; t += step) {
      grid.add(t);
    }
    // Snap nearby onsets onto grid (beat grid correction)
    if (onsets.isNotEmpty && grid.isNotEmpty) {
      for (var i = 0; i < grid.length; i++) {
        final g = grid[i];
        int? nearest;
        var best = 1 << 30;
        for (final o in onsets) {
          final d = (o - g).abs();
          if (d < best && d <= step ~/ 3) {
            best = d;
            nearest = o;
          }
        }
        if (nearest != null) grid[i] = nearest;
      }
    }
    return grid;
  }

  static List<EnergySegment> _energySegmentsFromTimeline(
    List<AudioFeatureSample> samples,
    int durationMs,
  ) {
    const segMs = 2000;
    final out = <EnergySegment>[];
    for (var start = 0; start < durationMs; start += segMs) {
      final end = math.min(durationMs, start + segMs);
      var sum = 0.0;
      var n = 0;
      for (final s in samples) {
        if (s.timeMs >= start && s.timeMs < end) {
          sum += s.features.gatedRms;
          n++;
        }
      }
      out.add(EnergySegment(
        startMs: start,
        endMs: end,
        energy: n == 0 ? 0 : (sum / n).clamp(0.0, 1.0),
      ));
    }
    return out;
  }

  static List<EnergySegment> _energySegmentsFromSeries(
    List<({int t, double v})> rms,
    int durationMs,
  ) {
    const segMs = 2000;
    final out = <EnergySegment>[];
    for (var start = 0; start < durationMs; start += segMs) {
      final end = math.min(durationMs, start + segMs);
      var sum = 0.0;
      var n = 0;
      for (final s in rms) {
        if (s.t >= start && s.t < end) {
          sum += s.v;
          n++;
        }
      }
      out.add(EnergySegment(
        startMs: start,
        endMs: end,
        energy: n == 0 ? 0 : (sum / n).clamp(0.0, 1.0),
      ));
    }
    return out;
  }

  static List<SilenceRange> _silenceFromTimeline(
    List<AudioFeatureSample> samples,
    int durationMs,
  ) {
    const thr = 0.06;
    const minLen = 400;
    final out = <SilenceRange>[];
    int? start;
    for (final s in samples) {
      final quiet = s.features.gatedRms < thr;
      if (quiet) {
        start ??= s.timeMs;
      } else if (start != null) {
        if (s.timeMs - start >= minLen) {
          out.add(SilenceRange(startMs: start, endMs: s.timeMs));
        }
        start = null;
      }
    }
    if (start != null && durationMs - start >= minLen) {
      out.add(SilenceRange(startMs: start, endMs: durationMs));
    }
    return out;
  }

  static List<SilenceRange> _silenceFromSeries(
    List<({int t, double v})> rms,
    int durationMs,
  ) {
    const thr = 0.08;
    const minLen = 400;
    final out = <SilenceRange>[];
    int? start;
    for (final s in rms) {
      final quiet = s.v < thr;
      if (quiet) {
        start ??= s.t;
      } else if (start != null) {
        if (s.t - start >= minLen) {
          out.add(SilenceRange(startMs: start, endMs: s.t));
        }
        start = null;
      }
    }
    if (start != null && durationMs - start >= minLen) {
      out.add(SilenceRange(startMs: start, endMs: durationMs));
    }
    return out;
  }

  static List<int> _filterCandidates({
    required List<int> onsets,
    required List<int> grid,
    required List<SilenceRange> silence,
    required List<EnergySegment> energy,
  }) {
    bool inSilence(int t) {
      for (final s in silence) {
        if (t >= s.startMs && t <= s.endMs) return true;
      }
      return false;
    }

    double energyAt(int t) {
      for (final e in energy) {
        if (t >= e.startMs && t < e.endMs) return e.energy;
      }
      return 0.4;
    }

    final set = <int>{};
    for (final o in onsets) {
      if (!inSilence(o) && energyAt(o) > 0.12) set.add(o);
    }
    for (final g in grid) {
      if (!inSilence(g) && energyAt(g) > 0.18) set.add(g);
    }
    final list = set.toList()..sort();
    // Avoid dense packing in quiet gaps
    final cleaned = <int>[];
    for (final t in list) {
      if (cleaned.isEmpty || t - cleaned.last >= 70) cleaned.add(t);
    }
    return cleaned;
  }

  static Future<(List<double>, int)?> _tryDecodeWav(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.length < 44) return null;
      final bd = ByteData.sublistView(bytes);
      // RIFF/WAVE
      if (bd.getUint32(0, Endian.little) != 0x46464952) return null;
      if (bd.getUint32(8, Endian.little) != 0x45564157) return null;

      var offset = 12;
      int? sampleRate;
      int? channels;
      int? bits;
      int? dataOffset;
      int? dataSize;

      while (offset + 8 <= bytes.length) {
        final id = bd.getUint32(offset, Endian.little);
        final size = bd.getUint32(offset + 4, Endian.little);
        offset += 8;
        if (id == 0x20746D66) {
          // fmt
          channels = bd.getUint16(offset + 2, Endian.little);
          sampleRate = bd.getUint32(offset + 4, Endian.little);
          bits = bd.getUint16(offset + 14, Endian.little);
        } else if (id == 0x61746164) {
          dataOffset = offset;
          dataSize = size;
          break;
        }
        offset += size + (size.isOdd ? 1 : 0);
      }

      if (sampleRate == null ||
          channels == null ||
          bits == null ||
          dataOffset == null ||
          dataSize == null) {
        return null;
      }
      if (bits != 16) return null;

      final samples = <double>[];
      final end = math.min(bytes.length, dataOffset + dataSize);
      for (var i = dataOffset; i + 2 <= end; i += 2 * channels) {
        final s = bd.getInt16(i, Endian.little) / 32768.0;
        samples.add(s);
      }
      return (samples, sampleRate);
    } catch (_) {
      return null;
    }
  }

  /// 截取音量最高的有效片段（轮播前对每段声音调用）。
  ///
  /// 优先用 AudioDrive 时间线的 gatedRms；WAV 则用 PCM RMS 滑窗。
  /// 窗口默认约 0.8–2.0s，落在整段能量峰值处。
  static Future<HotClip> findHottestClip({
    required int durationMs,
    String? audioPath,
    String? featuresPath,
    AudioFeatureTimeline? timeline,
    int? preferredWindowMs,
  }) async {
    final dur = durationMs.clamp(200, 180000).toInt();
    final windowMs = (preferredWindowMs ?? _defaultHotWindow(dur))
        .clamp(200, math.min(dur, 4000))
        .toInt();

    AudioFeatureTimeline? tl = timeline;
    if (tl == null && featuresPath != null) {
      final f = File(featuresPath);
      if (await f.exists()) {
        try {
          tl = AudioFeatureTimeline.decode(await f.readAsBytes());
        } catch (_) {}
      }
    }

    if (audioPath != null && audioPath.toLowerCase().endsWith('.wav')) {
      final decoded = await _tryDecodeWav(audioPath);
      if (decoded != null && decoded.$1.isNotEmpty) {
        return _hottestFromPcm(
          pcm: decoded.$1,
          sampleRate: decoded.$2,
          windowMs: windowMs,
        );
      }
    }

    if (tl != null && tl.samples.isNotEmpty) {
      return _hottestFromTimeline(tl, windowMs: windowMs, durationMs: dur);
    }

    // 无特征时：取中间一段作为保守有效区
    final start = math.max(0, (dur - windowMs) ~/ 2);
    return HotClip(startMs: start, durationMs: windowMs, peakEnergy: 0.4);
  }

  static int _defaultHotWindow(int durationMs) {
    if (durationMs <= 1200) return math.max(200, durationMs);
    if (durationMs <= 4000) return 800;
    if (durationMs <= 15000) return 1200;
    return 2000;
  }

  static HotClip _hottestFromTimeline(
    AudioFeatureTimeline tl, {
    required int windowMs,
    required int durationMs,
  }) {
    final samples = tl.samples;
    if (samples.isEmpty) {
      return HotClip(startMs: 0, durationMs: windowMs);
    }

    final hop = math.max(25, windowMs ~/ 20);
    var bestStart = 0;
    var bestScore = -1.0;
    final lastT = math.max(windowMs, durationMs);

    for (var start = 0; start + windowMs <= lastT; start += hop) {
      final end = start + windowMs;
      var sum = 0.0;
      var n = 0;
      var peak = 0.0;
      for (final s in samples) {
        if (s.timeMs < start) continue;
        if (s.timeMs >= end) break;
        final v = s.features.gatedRms;
        sum += v;
        n++;
        if (v > peak) peak = v;
      }
      if (n == 0) continue;
      // 均值 + 峰值加权，偏向持续响亮且有冲刺的段落
      final score = (sum / n) * 0.7 + peak * 0.3;
      if (score > bestScore) {
        bestScore = score;
        bestStart = start;
      }
    }

    // 向两侧扩展到仍高于峰值 45% 的连续区，避免切得过碎
    final expandThr = bestScore * 0.45;
    var left = bestStart;
    var right = bestStart + windowMs;
    while (left > 0) {
      final e = tl.sampleAt(left).gatedRms;
      if (e < expandThr) break;
      left = math.max(0, left - hop);
    }
    while (right < durationMs) {
      final e = tl.sampleAt(right).gatedRms;
      if (e < expandThr) break;
      right = math.min(durationMs, right + hop);
    }
    final clipDur =
        math.max(windowMs, right - left).clamp(200, durationMs).toInt();
    final start =
        left.clamp(0, math.max(0, durationMs - clipDur)).toInt();
    return HotClip(
      startMs: start,
      durationMs: clipDur,
      peakEnergy: bestScore.clamp(0.0, 1.0),
    );
  }

  static HotClip _hottestFromPcm({
    required List<double> pcm,
    required int sampleRate,
    required int windowMs,
  }) {
    final win = math.max(1, (windowMs / 1000 * sampleRate).round());
    final hop = math.max(1, win ~/ 20);
    if (pcm.length <= win) {
      return HotClip(
        startMs: 0,
        durationMs:
            ((pcm.length / sampleRate) * 1000).round().clamp(200, windowMs).toInt(),
        peakEnergy: 1,
      );
    }

    var bestI = 0;
    var bestScore = -1.0;
    for (var i = 0; i + win <= pcm.length; i += hop) {
      var sum = 0.0;
      var peak = 0.0;
      for (var j = i; j < i + win; j++) {
        final a = pcm[j].abs();
        sum += a;
        if (a > peak) peak = a;
      }
      final mean = sum / win;
      final score = mean * 0.7 + peak * 0.3;
      if (score > bestScore) {
        bestScore = score;
        bestI = i;
      }
    }

    final startMs = ((bestI / sampleRate) * 1000).round();
    return HotClip(
      startMs: startMs,
      durationMs: windowMs,
      peakEnergy: bestScore.clamp(0.0, 1.0),
    );
  }
}
