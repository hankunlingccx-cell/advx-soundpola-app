import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'beat_ai_api_config.dart';
import 'beat_models.dart';
import 'beat_planner.dart';

/// 阿卡贝拉编排 API：只收 FeatureSummary（含 HotClip / sourceRoles），只回 BeatPlan。
/// events 描述何时触发哪一段声部；不返回音频文件。
abstract class BeatGenerationApi {
  Future<BeatPlan> generate({
    required FeatureSummary summary,
    required int seed,
  });
}

/// 本地：AcapellaPlanner 随机编排。
class LocalBeatGenerationApi implements BeatGenerationApi {
  const LocalBeatGenerationApi();

  @override
  Future<BeatPlan> generate({
    required FeatureSummary summary,
    required int seed,
  }) async {
    return BeatPlanner.generate(summary: summary, seed: seed);
  }
}

/// AI / 远端模型接入：URL 与开关见 [BeatAiApiConfig]。
class AiBeatGenerationApi implements BeatGenerationApi {
  AiBeatGenerationApi({
    http.Client? httpClient,
    this.fallback = const LocalBeatGenerationApi(),
  }) : _http = httpClient ?? http.Client();

  final BeatGenerationApi fallback;
  final http.Client _http;

  @override
  Future<BeatPlan> generate({
    required FeatureSummary summary,
    required int seed,
  }) async {
    if (!BeatAiApiConfig.isEnabled) {
      return fallback.generate(summary: summary, seed: seed);
    }

    final uri = BeatAiApiConfig.endpointUri;
    if (uri == null) {
      debugPrint('[BeatAI] URL 无效，回退本地');
      return fallback.generate(summary: summary, seed: seed);
    }

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      final key = BeatAiApiConfig.resolvedApiKey;
      if (key.isNotEmpty) {
        headers['Authorization'] = 'Bearer $key';
      }

      final body = <String, dynamic>{
        ...summary.toJson(),
        'seed': seed,
        'mode': 'acapella',
      };

      // ★ AI API：POST FeatureSummary → 阿卡贝拉 BeatPlan
      debugPrint('[BeatAI] POST $uri');
      final res = await _http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 45));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('[BeatAI] ${res.statusCode} ${res.body} → 本地回退');
        return fallback.generate(summary: summary, seed: seed);
      }

      final plan = BeatPlanCodec.parseAndValidate(
        res.body,
        durationMs: mathMaxDuration(summary),
        sourceSoundId: summary.sourceSoundId,
        sourceCount: summary.sourceCount,
      );

      // AI 给了随机节拍型但 events 过少：用该节拍本地铺事件
      if (plan.events.length < 4 && plan.rhythmHits.length >= 3) {
        final rhythm = RhythmPattern.tryParse(
          hits: plan.rhythmHits,
          label: plan.rhythmLabel,
        );
        if (rhythm != null) {
          debugPrint('[BeatAI] 使用 AI 节拍「${rhythm.label}」本地铺轨');
          return AcapellaPlanner.generate(
            summary: summary,
            seed: seed,
            aiRhythm: rhythm,
          );
        }
      }
      return plan;
    } catch (e, st) {
      debugPrint('[BeatAI] failed: $e\n$st → 本地回退');
      return fallback.generate(summary: summary, seed: seed);
    }
  }

  static int mathMaxDuration(FeatureSummary s) {
    var maxMs = s.durationMs;
    for (final d in s.sourceDurationsMs) {
      if (d > maxMs) maxMs = d;
    }
    return maxMs < 1000 ? 8000 : maxMs;
  }
}

/// 全局入口：当前强制本地程序随机节拍；日后接 AI 改回 `AiBeatGenerationApi()`。
class BeatGenerationApiGateway {
  BeatGenerationApiGateway._();

  static BeatGenerationApi instance = const LocalBeatGenerationApi();
}
