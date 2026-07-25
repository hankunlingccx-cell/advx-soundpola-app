import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../cloud/cloud_media_config.dart';
import 'beat_models.dart';
import 'beat_planner.dart';

/// 节拍轮播 API：只收 FeatureSummary（含 sourceCount），只回 BeatPlan。
/// BeatPlan.events 描述「何时切换到哪一段已选声音」，不返回音频文件。
abstract class BeatGenerationApi {
  Future<BeatPlan> generate({
    required FeatureSummary summary,
    required int seed,
  });
}

/// 默认：本地确定性 BeatPlanner（无网络）。
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

/// 远端 API 接入点。
///
/// 接线方式：
/// 1. 设置 [endpointOverride]，或依赖 CloudMedia 同源路径
///    `POST {base}/api/v1/lab/beat-plan`
/// 2. 请求体：FeatureSummary JSON（可附带 seed）
/// 3. 响应体：BeatPlan JSON（仅 events / bpm 等结构化字段）
///
/// 当前服务端未就绪时自动回退 [LocalBeatGenerationApi]。
class RemoteBeatGenerationApi implements BeatGenerationApi {
  RemoteBeatGenerationApi({
    this.endpointOverride,
    this.enabled = false,
    http.Client? httpClient,
    this.fallback = const LocalBeatGenerationApi(),
  }) : _http = httpClient ?? http.Client();

  /// 完整 URL，例如 `https://api.example.com/v1/lab/beat-plan`。
  /// 为空时使用 [defaultEndpoint]。
  final String? endpointOverride;

  /// 设为 true 后才会真正请求远端；false 时直接走本地。
  final bool enabled;

  /// 远端失败或未启用时回退。
  final BeatGenerationApi fallback;

  final http.Client _http;

  /// 默认相对 Cloud Media base 的路径——服务端实现后只需打开 [enabled]。
  static Uri defaultEndpoint() =>
      CloudMediaConfig.uri('/api/v1/lab/beat-plan');

  Uri get endpoint {
    final raw = endpointOverride?.trim();
    if (raw != null && raw.isNotEmpty) return Uri.parse(raw);
    return defaultEndpoint();
  }

  @override
  Future<BeatPlan> generate({
    required FeatureSummary summary,
    required int seed,
  }) async {
    if (!enabled) {
      return fallback.generate(summary: summary, seed: seed);
    }

    try {
      final body = <String, dynamic>{
        ...summary.toJson(),
        'seed': seed,
      };
      // ── API hook：此处发起 HTTP；响应必须是 BeatPlan JSON ──
      final res = await _http
          .post(
            endpoint,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint(
          '[BeatGenerationApi] remote ${res.statusCode}, fallback local',
        );
        return fallback.generate(summary: summary, seed: seed);
      }

      return BeatPlanCodec.parseAndValidate(
        res.body,
        durationMs: summary.durationMs,
        sourceSoundId: summary.sourceSoundId,
        sourceCount: summary.sourceCount,
      );
    } catch (e, st) {
      debugPrint('[BeatGenerationApi] remote failed: $e\n$st');
      return fallback.generate(summary: summary, seed: seed);
    }
  }
}

/// App 全局入口：切换本地 / 远端只需改这里。
class BeatGenerationApiGateway {
  BeatGenerationApiGateway._();

  /// 正式接 API 时改为：
  /// `RemoteBeatGenerationApi(enabled: true)`
  /// 或注入自定义 endpoint。
  static BeatGenerationApi instance = RemoteBeatGenerationApi(
    enabled: false, // TODO: 后端就绪后改为 true
  );
}
