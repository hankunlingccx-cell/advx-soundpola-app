import 'dart:convert';
import 'dart:math';

import 'beat_models.dart';

/// 本地节拍轮播规划：按拍点轮流切换已选声音（不生成鼓点 one-shot）。
class BeatPlanner {
  BeatPlanner._();

  static const version = 'local_rotate_planner_v1';

  /// [summary.sourceCount] / [summary.sourceDurationsMs] 决定轮播对象。
  static BeatPlan generate({
    required FeatureSummary summary,
    required int seed,
    BeatStyle? style,
    BeatDensity? density,
  }) {
    final dens = density ?? BeatDensity.parse(summary.requestedDensity);
    final st = style ?? BeatStyle.parse(summary.requestedStyle);
    final rng = Random(seed);

    final sourceCount = max(1, summary.sourceCount);
    final durations = List<int>.generate(sourceCount, (i) {
      if (i < summary.sourceDurationsMs.length &&
          summary.sourceDurationsMs[i] > 0) {
        return summary.sourceDurationsMs[i];
      }
      return max(1000, summary.durationMs);
    });

    final bpm = summary.estimatedBpm <= 0 ? 90.0 : summary.estimatedBpm;
    final step = max(180, (60000 / bpm).round());

    // 密度：稀疏=每 2 拍换一次；平衡=每拍；密集=每半拍
    final slotMs = switch (dens) {
      BeatDensity.sparse => step * 2,
      BeatDensity.balanced => step,
      BeatDensity.dense => max(120, step ~/ 2),
    };

    // 轮播总长：至少 8 小节，或主声音时长
    final bars = 8;
    final planDuration = max(
      summary.durationMs,
      slotMs * sourceCount * bars,
    );

    bool inSilence(int t) {
      for (final s in summary.silenceRanges) {
        if (t >= s.startMs && t <= s.endMs) return true;
      }
      return false;
    }

    final events = <BeatEvent>[];
    var rotate = 0;
    // 可选：从 seed 决定起始音源
    rotate = seed % sourceCount;

    for (var t = 0; t < planDuration; t += slotMs) {
      if (inSilence(t) && dens != BeatDensity.dense) {
        // 静音区跳过换源，但仍推进时间
        continue;
      }

      final src = rotate % sourceCount;
      rotate++;

      final srcDur = durations[src];
      // 切片：优先对齐 onset，否则按拍推进
      var slice = 0;
      if (summary.onsetsMs.isNotEmpty && srcDur > slotMs) {
        final onset = summary.onsetsMs[rng.nextInt(summary.onsetsMs.length)];
        slice = onset.clamp(0, max(0, srcDur - slotMs));
      } else if (srcDur > slotMs) {
        slice = ((t ~/ slotMs) * (slotMs ~/ 2)) % max(1, srcDur - slotMs);
      }

      final isDown = events.length % 4 == 0;
      // groove：偶拍略偏左/右；glitch：偶发跳源
      var pan = 0.0;
      if (st == BeatStyle.groove) {
        pan = (src / max(1, sourceCount - 1)) * 2 - 1;
      } else if (st == BeatStyle.glitch && rng.nextDouble() < 0.15) {
        // 随机再跳一次
        rotate++;
      }

      events.add(
        BeatEvent(
          id: 'rot_${t}_$src',
          timeMs: t,
          sourceIndex: src,
          playDurationMs: slotMs,
          sliceOffsetMs: slice,
          strength: isDown ? 1.0 : 0.75,
          volume: isDown ? 0.95 : 0.8,
          pan: pan.clamp(-1.0, 1.0),
          generated: true,
          isDownbeat: isDown,
        ),
      );
    }

    final cleaned = BeatPlanCodec.sanitizeEvents(
      events,
      durationMs: planDuration,
      sourceCount: sourceCount,
    );

    return BeatPlan(
      id: 'plan_${seed.toRadixString(16)}_$planDuration',
      sourceSoundId: summary.sourceSoundId,
      estimatedBpm: bpm,
      seed: seed,
      generatorVersion: version,
      events: cleaned,
      style: st,
      density: dens,
    );
  }
}

/// Import / export / validate BeatPlan & FeatureSummary JSON.
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
        // 同拍冲突：保留后一个（轮播切换）
        out[out.length - 1] = cur;
      } else {
        out.add(cur);
      }
    }
    return out;
  }
}
