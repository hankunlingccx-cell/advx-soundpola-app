import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'beat_ai_api_config.dart';
import 'beat_models.dart';
import 'beat_planner.dart';

/// 节拍轮播 API：只收 FeatureSummary（含 sourceCount），只回 BeatPlan。
/// events 描述「何时切换到哪一段已选声音」，不返回音频文件。
abstract class BeatGenerationApi {
  Future<BeatPlan> generate({
    required FeatureSummary summary,
    required int seed,
  });
}

/// 本地：根据所选内容特征做随机轮播计划。
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
        'mode': 'beat_rotate',
      };

      // ★ AI API 实际请求点：POST FeatureSummary → BeatPlan
      debugPrint('[BeatAI] POST $uri');
      final res = await _http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 45));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('[BeatAI] ${res.statusCode} ${res.body} → 本地回退');
        return fallback.generate(summary: summary, seed: seed);
      }

      return BeatPlanCodec.parseAndValidate(
        res.body,
        durationMs: mathMaxDuration(summary),
        sourceSoundId: summary.sourceSoundId,
        sourceCount: summary.sourceCount,
      );
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

/// 全局入口：默认走 AI 配置；未启用时自动本地随机。
class BeatGenerationApiGateway {
  BeatGenerationApiGateway._();

  /// 接 AI 时只需改 [BeatAiApiConfig.endpointUrl] + [BeatAiApiConfig.enabled]。
  static BeatGenerationApi instance = AiBeatGenerationApi();
}
