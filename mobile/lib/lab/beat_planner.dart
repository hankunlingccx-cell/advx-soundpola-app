import 'dart:convert';
import 'dart:math';

import 'beat_models.dart';

/// 随机节拍型：AI 应返回同类结构；本地为回退。
/// hits：1≈咚（重）、0.55≈打（轻）、0=休止(-)。
class RhythmPattern {
  const RhythmPattern({
    required this.hits,
    required this.label,
  });

  final List<double> hits;
  final String label;

  int get length => hits.length;

  /// 用 seed 随机发明一小节节拍（非固定模板）。
  factory RhythmPattern.invent(Random rng, {BeatDensity? density}) {
    final dens = density ?? BeatDensity.balanced;
    final len = switch (dens) {
      BeatDensity.sparse => 4 + rng.nextInt(2), // 4–5
      BeatDensity.balanced => 5 + rng.nextInt(3), // 5–7
      BeatDensity.dense => 6 + rng.nextInt(3), // 6–8
    };

    final hits = <double>[];
    // 首拍倾向重击
    hits.add(rng.nextDouble() < 0.85 ? 1.0 : 0.7);
    for (var i = 1; i < len; i++) {
      final roll = rng.nextDouble();
      if (dens == BeatDensity.sparse) {
        if (roll < 0.35) {
          hits.add(0);
        } else if (roll < 0.55) {
          hits.add(0.5 + rng.nextDouble() * 0.15);
        } else {
          hits.add(0.85 + rng.nextDouble() * 0.15);
        }
      } else if (dens == BeatDensity.dense) {
        if (roll < 0.12) {
          hits.add(0);
        } else if (roll < 0.45) {
          hits.add(0.45 + rng.nextDouble() * 0.2);
        } else {
          hits.add(0.8 + rng.nextDouble() * 0.2);
        }
      } else {
        // balanced：可出现「咚咚打咚咚-」一类疏密
        if (roll < 0.22) {
          hits.add(0);
        } else if (roll < 0.48) {
          hits.add(0.5 + rng.nextDouble() * 0.15);
        } else {
          hits.add(0.85 + rng.nextDouble() * 0.15);
        }
      }
    }
    // 避免全空或全满：保证至少 2 击、至多 len-1 击（len>3 时留休止机会）
    final hitCount = hits.where((h) => h > 0.05).length;
    if (hitCount < 2) {
      hits[rng.nextInt(len)] = 1.0;
      hits[rng.nextInt(len)] = 0.55;
    }
    if (len > 3 && hitCount == len) {
      hits[1 + rng.nextInt(len - 1)] = 0;
    }

    return RhythmPattern(hits: hits, label: labelFromHits(hits));
  }

  /// 从 AI 返回的 hits / label 恢复；无效则 null。
  static RhythmPattern? tryParse({
    List<double>? hits,
    String? label,
  }) {
    if (hits == null || hits.isEmpty) return null;
    final cleaned = hits.map((h) => h.clamp(0.0, 1.0)).toList();
    final lab =
        (label != null && label.trim().isNotEmpty) ? label.trim() : labelFromHits(cleaned);
    return RhythmPattern(hits: cleaned, label: lab);
  }

  static String labelFromHits(List<double> hits) {
    final buf = StringBuffer();
    for (final h in hits) {
      if (h < 0.08) {
        buf.write('-');
      } else if (h < 0.7) {
        buf.write('打');
      } else {
        buf.write('咚');
      }
    }
    return buf.toString();
  }
}

class BeatPlanner {
  BeatPlanner._();

  static const version = BeatPlan.generatorVersionLocal;

  static BeatPlan generate({
    required FeatureSummary summary,
    required int seed,
    BeatStyle? style,
    BeatDensity? density,
  }) =>
      AcapellaPlanner.generate(
        summary: summary,
        seed: seed,
        style: style,
        density: density,
      );
}

/// 自动化声音阿卡贝拉：先随机生成节拍型，再把 HotClip 填进拍点。
///
/// 节拍应由 AI 随机发明（rhythmHits + rhythmLabel）；
/// 未接 API 时本地 [RhythmPattern.invent] 回退。
class AcapellaPlanner {
  AcapellaPlanner._();

  static const version = BeatPlan.generatorVersionLocal;
  static const maxLayers = 2;

  static BeatPlan generate({
    required FeatureSummary summary,
    required int seed,
    BeatStyle? style,
    BeatDensity? density,
    RhythmPattern? aiRhythm,
  }) {
    final rng = Random(seed ^ _fingerprint(summary));
    final dens = density ?? _pickDensity(summary, rng);
    final st = style ?? _pickStyle(summary, rng);

    final sourceCount = max(1, summary.sourceCount);
    final roles = _resolveRoles(summary, sourceCount);
    final durations = List<int>.generate(sourceCount, (i) {
      if (i < summary.sourceDurationsMs.length &&
          summary.sourceDurationsMs[i] > 0) {
        return summary.sourceDurationsMs[i];
      }
      return max(1000, summary.durationMs);
    });
    final hots = List<HotClip>.generate(sourceCount, (i) {
      if (i < summary.sourceHotClips.length) return summary.sourceHotClips[i];
      final d = durations[i];
      final w = min(1200, d);
      return HotClip(startMs: max(0, (d - w) ~/ 2), durationMs: w);
    });

    var bpm = summary.estimatedBpm <= 0 ? 92.0 : summary.estimatedBpm;
    bpm = (bpm * (0.94 + rng.nextDouble() * 0.12)).clamp(76.0, 140.0);
    final step = max(160, (60000 / bpm).round());

    // ★ 节拍：优先 AI 提供的随机型，否则本地随机发明
    final rhythm = aiRhythm ?? RhythmPattern.invent(rng, density: dens);
    final slotMs = max(120, step); // 每「咚/打/-」一拍位
    final bars = 8 + rng.nextInt(5);
    final planDuration = max(
      summary.durationMs,
      slotMs * rhythm.length * bars,
    );

    bool inSilence(int t) {
      for (final s in summary.silenceRanges) {
        if (t >= s.startMs && t <= s.endMs) return true;
      }
      return false;
    }

    int indexOfRole(AcapellaRole role) {
      final i = roles.indexOf(role);
      return i >= 0 ? i : 0;
    }

    final leadIdx = indexOfRole(AcapellaRole.lead);
    final responseIdx = roles.contains(AcapellaRole.response)
        ? indexOfRole(AcapellaRole.response)
        : (sourceCount > 1 ? 1 % sourceCount : 0);
    final padIdx = roles.contains(AcapellaRole.pad)
        ? indexOfRole(AcapellaRole.pad)
        : leadIdx;
    final percIdx = roles.contains(AcapellaRole.percussion)
        ? indexOfRole(AcapellaRole.percussion)
        : (sourceCount > 1 ? sourceCount - 1 : 0);

    final events = <BeatEvent>[];

    void addEvent({
      required int timeMs,
      required int sourceIndex,
      required AcapellaRole role,
      required int playMs,
      required bool isDown,
      required double volume,
      required double pan,
      required double strength,
    }) {
      if (timeMs < 0 || timeMs > planDuration) return;
      if (inSilence(timeMs) && role == AcapellaRole.pad) return;

      final hot = hots[sourceIndex.clamp(0, hots.length - 1)];
      final srcDur = durations[sourceIndex.clamp(0, durations.length - 1)];
      var dur = min(playMs, max(80, hot.durationMs));
      // 重击略长、轻击更短
      if (strength < 0.7) dur = min(dur, max(80, (slotMs * 0.55).round()));
      final room = max(0, hot.durationMs - dur);
      final jitter = room > 0 ? rng.nextInt(min(room + 1, 80)) : 0;
      final slice =
          (hot.startMs + jitter).clamp(0, max(0, srcDur - dur)).toInt();

      events.add(
        BeatEvent(
          id: 'aca_${timeMs}_${role.name}_$sourceIndex'
              '_${rng.nextInt(1 << 12).toRadixString(16)}',
          timeMs: timeMs,
          sourceIndex: sourceIndex,
          playDurationMs: dur,
          sliceOffsetMs: slice,
          strength: strength.clamp(0.05, 1.0),
          volume: volume.clamp(0.2, 1.0),
          pan: pan.clamp(-1.0, 1.0),
          generated: true,
          isDownbeat: isDown,
          role: role,
        ),
      );
    }

    // ── 主循环：按随机节拍型铺底（咚/打 用不同声源 HotClip）──
    var rotate = rng.nextInt(sourceCount);
    for (var t = 0, slot = 0; t < planDuration; t += slotMs, slot++) {
      final hit = rhythm.hits[slot % rhythm.length];
      if (hit < 0.08) continue; // 休止 -
      if (inSilence(t) && hit < 0.9) continue;

      final isHeavy = hit >= 0.7;
      final isDown = slot % rhythm.length == 0;

      // 重击：主声或节奏源；轻击：应答/轮转
      int src;
      AcapellaRole role;
      if (isHeavy) {
        if (isDown || rng.nextDouble() < 0.55) {
          src = leadIdx;
          role = AcapellaRole.lead;
        } else {
          src = percIdx;
          role = sourceCount > 1
              ? AcapellaRole.percussion
              : AcapellaRole.lead;
        }
      } else {
        src = responseIdx;
        role = sourceCount > 1
            ? AcapellaRole.response
            : AcapellaRole.lead;
        // 偶尔轮到下一源，增加层次感
        if (sourceCount > 2 && rng.nextDouble() < 0.35) {
          src = rotate % sourceCount;
          rotate++;
        }
      }

      final pan = st == BeatStyle.minimal
          ? 0.0
          : ((src / max(1, sourceCount - 1)) * 2 - 1) * 0.45;

      addEvent(
        timeMs: t,
        sourceIndex: src,
        role: role,
        playMs: isHeavy ? slotMs : max(80, (slotMs * 0.6).round()),
        isDown: isDown && isHeavy,
        volume: isHeavy ? 0.85 + hit * 0.12 : 0.55 + hit * 0.25,
        pan: pan + (rng.nextDouble() - 0.5) * 0.15,
        strength: hit,
      );

      // 强拍偶发衬底叠唱（第 2 层）
      if (isHeavy &&
          isDown &&
          sourceCount > 2 &&
          padIdx != src &&
          rng.nextDouble() < 0.55) {
        addEvent(
          timeMs: t,
          sourceIndex: padIdx,
          role: AcapellaRole.pad,
          playMs: slotMs,
          isDown: true,
          volume: 0.35 + rng.nextDouble() * 0.15,
          pan: -pan * 0.6,
          strength: hit * 0.7,
        );
      }
    }

    final cleaned = BeatPlanCodec.sanitizeEvents(
      events,
      durationMs: planDuration,
      sourceCount: sourceCount,
      maxLayers: maxLayers,
    );

    return BeatPlan(
      id: 'aca_${seed.toRadixString(16)}_$planDuration',
      sourceSoundId: summary.sourceSoundId,
      estimatedBpm: double.parse(bpm.toStringAsFixed(1)),
      seed: seed,
      generatorVersion: version,
      events: cleaned,
      style: st,
      density: dens,
      rhythmLabel: rhythm.label,
      rhythmHits: rhythm.hits,
    );
  }

  /// AI 返回的 BeatPlan 若带 rhythmHits，可用于本地补全；通常直接用 events。
  static RhythmPattern? rhythmFromPlanFields(BeatPlan plan) {
    return RhythmPattern.tryParse(
      hits: plan.rhythmHits.isEmpty ? null : plan.rhythmHits,
      label: plan.rhythmLabel,
    );
  }

  static List<AcapellaRole> _resolveRoles(FeatureSummary s, int count) {
    if (s.sourceRoles.length >= count) {
      return s.sourceRoles.take(count).toList();
    }
    return AcapellaRole.assignDefaults(count);
  }

  static int _fingerprint(FeatureSummary s) {
    var h = s.sourceCount * 1315423911;
    h ^= s.durationMs;
    h ^= (s.estimatedBpm * 100).round();
    h ^= s.onsetsMs.length * 2654435761;
    for (final d in s.sourceDurationsMs) {
      h = 0x1fffffff & (h * 31 + d);
    }
    for (final c in s.sourceHotClips) {
      h = 0x1fffffff & (h * 31 + c.startMs + c.durationMs);
    }
    h ^= s.sourceSoundId.hashCode;
    return h;
  }

  static BeatDensity _pickDensity(FeatureSummary s, Random rng) {
    final onsetRate = s.durationMs <= 0
        ? 0.0
        : s.onsetsMs.length / (s.durationMs / 1000.0);
    if (onsetRate > 2.5) {
      return rng.nextDouble() < 0.65 ? BeatDensity.dense : BeatDensity.balanced;
    }
    if (onsetRate < 0.8) {
      return rng.nextDouble() < 0.6 ? BeatDensity.sparse : BeatDensity.balanced;
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
      return rng.nextDouble() < 0.45 ? BeatStyle.glitch : BeatStyle.groove;
    }
    if (avgE < 0.3) return BeatStyle.minimal;
    final roll = rng.nextDouble();
    if (roll < 0.4) return BeatStyle.minimal;
    if (roll < 0.85) return BeatStyle.groove;
    return BeatStyle.glitch;
  }
}

abstract final class BeatPlanCodec {
  static const mergeMsDefault = 30;

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
    // 若 AI 只给了 rhythmHits 而 events 很少，用本地按该节拍铺事件
    var events = plan.events;
    if (events.length < 4 && plan.rhythmHits.length >= 3) {
      final rhythm = RhythmPattern.tryParse(
        hits: plan.rhythmHits,
        label: plan.rhythmLabel,
      );
      if (rhythm != null) {
        // 无法在此重建完整 FeatureSummary；保留 AI events，仅 sanitize
      }
    }

    events = sanitizeEvents(
      events,
      durationMs: durationMs,
      sourceCount: sourceCount,
      mergeMs: mergeMs,
      maxLayers: AcapellaPlanner.maxLayers,
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
      rhythmLabel: plan.rhythmLabel.isNotEmpty
          ? plan.rhythmLabel
          : (plan.rhythmHits.isNotEmpty
              ? RhythmPattern.labelFromHits(plan.rhythmHits)
              : ''),
      rhythmHits: plan.rhythmHits,
    );
  }

  static List<BeatEvent> sanitizeEvents(
    List<BeatEvent> events, {
    required int durationMs,
    int sourceCount = 1,
    int mergeMs = mergeMsDefault,
    int maxLayers = 2,
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
      ..sort((a, b) {
        final c = a.timeMs.compareTo(b.timeMs);
        if (c != 0) return c;
        return a.role.index.compareTo(b.role.index);
      });

    final deduped = <BeatEvent>[];
    for (final e in clipped) {
      if (deduped.isNotEmpty) {
        final prev = deduped.last;
        if (prev.sourceIndex == e.sourceIndex &&
            (e.timeMs - prev.timeMs).abs() <= mergeMs) {
          if (e.strength >= prev.strength) {
            deduped[deduped.length - 1] = e;
          }
          continue;
        }
      }
      deduped.add(e);
    }

    final kept = <BeatEvent>[];
    for (final e in deduped) {
      final active = kept.where((k) {
        final end = k.timeMs + k.playDurationMs;
        return e.timeMs < end && (e.timeMs + e.playDurationMs) > k.timeMs;
      }).length;
      if (active < maxLayers) kept.add(e);
    }
    return kept;
  }
}
