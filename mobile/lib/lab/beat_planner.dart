import 'dart:convert';
import 'dart:math';

import 'beat_models.dart';

/// 本地随机轮播规划：根据所选内容特征 + seed 生成差异化节拍序列。
class BeatPlanner {
  BeatPlanner._();

  static const version = 'local_rotate_random_v2';

  static BeatPlan generate({
    required FeatureSummary summary,
    required int seed,
    BeatStyle? style,
    BeatDensity? density,
  }) {
    final rng = Random(seed ^ _contentFingerprint(summary));

    // 由内容能量 / onset 密度随机落在某种风格与疏密
    final dens = density ?? _pickDensity(summary, rng);
    final st = style ?? _pickStyle(summary, rng);

    final sourceCount = max(1, summary.sourceCount);
    final durations = List<int>.generate(sourceCount, (i) {
      if (i < summary.sourceDurationsMs.length &&
          summary.sourceDurationsMs[i] > 0) {
        return summary.sourceDurationsMs[i];
      }
      return max(1000, summary.durationMs);
    });

    // BPM：估测值附近抖动，避免每次完全一样
    var bpm = summary.estimatedBpm <= 0 ? 90.0 : summary.estimatedBpm;
    bpm = (bpm * (0.92 + rng.nextDouble() * 0.16)).clamp(72.0, 148.0);
    final baseStep = max(160, (60000 / bpm).round());

    final slotMs = switch (dens) {
      BeatDensity.sparse => baseStep * (rng.nextBool() ? 2 : 3),
      BeatDensity.balanced => baseStep,
      BeatDensity.dense => max(110, baseStep ~/ (rng.nextBool() ? 2 : 1)),
    };

    // 总长：随机 6–12 小节，并兼顾最长源
    final bars = 6 + rng.nextInt(7);
    final longest = durations.reduce(max);
    final planDuration = max(longest, slotMs * sourceCount * bars);

    bool inSilence(int t) {
      for (final s in summary.silenceRanges) {
        if (t >= s.startMs && t <= s.endMs) return true;
      }
      return false;
    }

    double energyAt(int t) {
      for (final e in summary.energySegments) {
        if (t >= e.startMs && t < e.endMs) return e.energy;
      }
      return 0.45;
    }

    // 随机排列顺序，再按权重抽选（长音频略高概率）
    final order = List<int>.generate(sourceCount, (i) => i)..shuffle(rng);
    final weights = List<double>.generate(sourceCount, (i) {
      final durW = (durations[i] / longest).clamp(0.35, 1.0);
      return durW * (0.6 + rng.nextDouble() * 0.8);
    });

    int pickSource(int avoid) {
      if (sourceCount == 1) return 0;
      // 70%：按权重；30%：顺着打乱顺序轮转
      if (rng.nextDouble() < 0.3) {
        final next = order[rng.nextInt(order.length)];
        if (next == avoid && sourceCount > 1) {
          return order[(order.indexOf(next) + 1) % order.length];
        }
        return next;
      }
      var sum = 0.0;
      for (var i = 0; i < sourceCount; i++) {
        if (i == avoid && sourceCount > 1) continue;
        sum += weights[i];
      }
      var r = rng.nextDouble() * sum;
      for (var i = 0; i < sourceCount; i++) {
        if (i == avoid && sourceCount > 1) continue;
        r -= weights[i];
        if (r <= 0) return i;
      }
      return rng.nextInt(sourceCount);
    }

    final events = <BeatEvent>[];
    var prevSrc = -1;
    var t = rng.nextInt(slotMs ~/ 3); // 随机相位起点

    while (t < planDuration) {
      // 静音区：有时拉长空拍
      if (inSilence(t) && dens != BeatDensity.dense) {
        t += slotMs * (1 + rng.nextInt(2));
        continue;
      }

      final e = energyAt(t);
      // 高能量区更短切片、更频繁切换
      var thisSlot = slotMs;
      if (e > 0.65 && dens != BeatDensity.sparse) {
        thisSlot = max(100, (slotMs * (0.55 + rng.nextDouble() * 0.35)).round());
      } else if (e < 0.25) {
        thisSlot = (slotMs * (1.2 + rng.nextDouble() * 0.8)).round();
      }
      // 偶发粘连：同一源连播 2 拍
      final sticky = dens == BeatDensity.sparse
          ? rng.nextDouble() < 0.45
          : rng.nextDouble() < 0.18;

      final src = sticky && prevSrc >= 0 ? prevSrc : pickSource(prevSrc);
      prevSrc = src;

      final srcDur = durations[src];
      // 优先落在该源「音量最高有效片段」内；仅在片段内做小抖动
      final hot = src < summary.sourceHotClips.length
          ? summary.sourceHotClips[src]
          : null;
      var slice = 0;
      var maxPlay = thisSlot;
      if (hot != null && hot.durationMs > 80) {
        maxPlay = min(thisSlot, hot.durationMs);
        thisSlot = maxPlay;
        final room = max(0, hot.durationMs - thisSlot);
        final jitter = room > 0 ? rng.nextInt(min(room + 1, 120)) : 0;
        slice = hot.startMs + jitter;
        slice = slice.clamp(0, max(0, srcDur - thisSlot));
      } else if (summary.onsetsMs.isNotEmpty && srcDur > thisSlot) {
        final onset = summary.onsetsMs[rng.nextInt(summary.onsetsMs.length)];
        final jitter = rng.nextInt(80) - 40;
        slice = (onset + jitter).clamp(0, max(0, srcDur - thisSlot));
      } else if (srcDur > thisSlot) {
        slice = rng.nextInt(max(1, srcDur - thisSlot));
      }

      final isDown = events.length % 4 == 0;
      var pan = 0.0;
      if (st == BeatStyle.groove) {
        pan = ((src / max(1, sourceCount - 1)) * 2 - 1) +
            (rng.nextDouble() - 0.5) * 0.25;
      } else if (st == BeatStyle.glitch) {
        pan = (rng.nextDouble() * 2 - 1) * 0.85;
        if (rng.nextDouble() < 0.2) {
          // glitch：极短切
          thisSlot = max(80, thisSlot ~/ 2);
        }
      }

      events.add(
        BeatEvent(
          id: 'rot_${t}_${src}_${rng.nextInt(1 << 16).toRadixString(16)}',
          timeMs: t,
          sourceIndex: src,
          playDurationMs: thisSlot,
          sliceOffsetMs: slice,
          strength: (isDown ? 0.85 : 0.55) + e * 0.2,
          volume: (0.7 + rng.nextDouble() * 0.25).clamp(0.4, 1.0),
          pan: pan.clamp(-1.0, 1.0),
          generated: true,
          isDownbeat: isDown,
        ),
      );

      t += thisSlot;
    }

    final cleaned = BeatPlanCodec.sanitizeEvents(
      events,
      durationMs: planDuration,
      sourceCount: sourceCount,
    );

    return BeatPlan(
      id: 'plan_${seed.toRadixString(16)}_$planDuration',
      sourceSoundId: summary.sourceSoundId,
      estimatedBpm: double.parse(bpm.toStringAsFixed(1)),
      seed: seed,
      generatorVersion: version,
      events: cleaned,
      style: st,
      density: dens,
    );
  }

  /// 把所选内容特征压成指纹，保证「同内容不同选」分布不同。
  static int _contentFingerprint(FeatureSummary s) {
    var h = s.sourceCount * 1315423911;
    h ^= s.durationMs;
    h ^= (s.estimatedBpm * 100).round();
    h ^= s.onsetsMs.length * 2654435761;
    for (final d in s.sourceDurationsMs) {
      h = 0x1fffffff & (h * 31 + d);
    }
    if (s.energySegments.isNotEmpty) {
      h ^= (s.energySegments.first.energy * 1000).round();
      h ^= (s.energySegments.last.energy * 1000).round();
    }
    h ^= s.sourceSoundId.hashCode;
    return h;
  }

  static BeatDensity _pickDensity(FeatureSummary s, Random rng) {
    final onsetRate = s.durationMs <= 0
        ? 0.0
        : s.onsetsMs.length / (s.durationMs / 1000.0);
    if (onsetRate > 2.5) {
      return rng.nextDouble() < 0.7 ? BeatDensity.dense : BeatDensity.balanced;
    }
    if (onsetRate < 0.8) {
      return rng.nextDouble() < 0.65 ? BeatDensity.sparse : BeatDensity.balanced;
    }
    final roll = rng.nextDouble();
    if (roll < 0.25) return BeatDensity.sparse;
    if (roll < 0.75) return BeatDensity.balanced;
    return BeatDensity.dense;
  }

  static BeatStyle _pickStyle(FeatureSummary s, Random rng) {
    final avgE = s.energySegments.isEmpty
        ? 0.4
        : s.energySegments.map((e) => e.energy).reduce((a, b) => a + b) /
            s.energySegments.length;
    if (avgE > 0.7) {
      return rng.nextDouble() < 0.5 ? BeatStyle.glitch : BeatStyle.groove;
    }
    if (avgE < 0.3) return BeatStyle.minimal;
    final roll = rng.nextDouble();
    if (roll < 0.4) return BeatStyle.minimal;
    if (roll < 0.8) return BeatStyle.groove;
    return BeatStyle.glitch;
  }
}

abstract final class BeatPlanCodec {
  static const mergeMsDefault = 40;

  static String encodeFeatureSummary(FeatureSummary s, {bool pretty = true}) {
    final encoder =
        pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    return encoder.convert(s.toJson());
  }

  static String encodeBeatPlan(BeatPlan plan, {bool pretty = true}) {
    final encoder =
        pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    return encoder.convert(plan.toJson());
  }

  static BeatPlan parseAndValidate(
    String raw, {
    required int durationMs,
    String? sourceSoundId,
    int sourceCount = 1,
    int mergeMs = mergeMsDefault,
  }) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('BeatPlan 根节点必须是 JSON 对象');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map.containsKey('pcm') ||
        map.containsKey('audioBase64') ||
        map.containsKey('audioFile')) {
      throw const FormatException('不允许包含音频文件字段，仅接受 BeatPlan 事件');
    }
    if (map['events'] is! List) {
      throw const FormatException('缺少 events 数组');
    }

    final plan = BeatPlan.fromJson(map);
    final events = sanitizeEvents(
      plan.events,
      durationMs: durationMs,
      sourceCount: sourceCount,
      mergeMs: mergeMs,
    );

    return BeatPlan(
      id: plan.id,
      sourceSoundId: sourceSoundId ?? plan.sourceSoundId,
      estimatedBpm: plan.estimatedBpm,
      seed: plan.seed,
      generatorVersion: plan.generatorVersion.isEmpty
          ? BeatPlan.generatorVersionCodex
          : plan.generatorVersion,
      events: events,
      style: plan.style,
      density: plan.density,
    );
  }

  static List<BeatEvent> sanitizeEvents(
    List<BeatEvent> events, {
    required int durationMs,
    int sourceCount = 1,
    int mergeMs = mergeMsDefault,
  }) {
    final n = max(1, sourceCount);
    final clipped = events
        .where((e) => e.timeMs >= 0 && e.timeMs <= durationMs)
        .map((e) => e.copyWith(
              sourceIndex: e.sourceIndex % n,
              playDurationMs: max(80, e.playDurationMs),
              sliceOffsetMs: max(0, e.sliceOffsetMs),
              strength: e.strength.clamp(0.0, 1.0),
              volume: e.volume.clamp(0.0, 1.0),
              pan: e.pan.clamp(-1.0, 1.0),
            ))
        .toList()
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return mergeNear(clipped, mergeMs: mergeMs);
  }

  static List<BeatEvent> mergeNear(List<BeatEvent> events, {int mergeMs = 40}) {
    if (events.isEmpty) return events;
    final sorted = [...events]..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    final out = <BeatEvent>[sorted.first];
    for (var i = 1; i < sorted.length; i++) {
      final prev = out.last;
      final cur = sorted[i];
      if (cur.timeMs - prev.timeMs <= mergeMs) {
        out[out.length - 1] = cur;
      } else {
        out.add(cur);
      }
    }
    return out;
  }
}
