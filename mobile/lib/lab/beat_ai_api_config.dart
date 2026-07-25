import 'package:shared_preferences/shared_preferences.dart';

/// ──────────────────────────────────────────────────────────────
/// ★ AI 阿卡贝拉 / 随机节拍 API（接模型只改这里）
/// ──────────────────────────────────────────────────────────────
///
/// 用法：
/// 1. 填 [endpointUrl]
/// 2. [enabled] = true
/// 3. 可选 [apiKey]
///
/// 请求：FeatureSummary + seed，且 requestRandomRhythm=true
/// 响应：BeatPlan，**必须随机发明节拍**，例如：
///   "rhythmLabel": "咚咚打咚咚-",
///   "rhythmHits": [1, 1, 0.55, 1, 1, 0],
///   "events": [ { timeMs, sourceIndex, playDurationMs, sliceOffsetMs, role, ... } ]
///
/// 每次请求应产生不同节奏（可用 seed）。不返回 PCM。
/// 失败时回退本地随机 [RhythmPattern.invent]。
class BeatAiApiConfig {
  BeatAiApiConfig._();

  // ─── 在此填写 AI API 链接 ───────────────────────────────────
  /// 例如：'https://api.example.com/v1/lab/beat-plan'
  /// 留空且 enabled=false 时走本地随机生成。
  static const String endpointUrl = '';

  /// 设为 true 后才会请求上方 URL。
  /// 当前网关已切到本地随机，即使 true 也不会走网络，除非改回 AiBeatGenerationApi。
  static const bool enabled = false;

  /// 可选：API Key（Bearer）。不需要可留空。
  static const String apiKey = '';
  // ───────────────────────────────────────────────────────────

  static const _prefsUrlKey = 'sp_beat_ai_api_url';
  static const _prefsEnabledKey = 'sp_beat_ai_api_enabled';
  static const _prefsKeyKey = 'sp_beat_ai_api_key';

  static const _envUrl = String.fromEnvironment('BEAT_AI_API_URL');
  static const _envEnabled = bool.fromEnvironment(
    'BEAT_AI_API_ENABLED',
    defaultValue: false,
  );
  static const _envKey = String.fromEnvironment('BEAT_AI_API_KEY');

  static String? _runtimeUrl;
  static bool? _runtimeEnabled;
  static String? _runtimeKey;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _runtimeUrl = prefs.getString(_prefsUrlKey);
    _runtimeEnabled = prefs.containsKey(_prefsEnabledKey)
        ? prefs.getBool(_prefsEnabledKey)
        : null;
    _runtimeKey = prefs.getString(_prefsKeyKey);
  }

  /// 运行时覆盖（可选，供调试页写入）。
  static Future<void> saveRuntime({
    String? url,
    bool? enabledFlag,
    String? key,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (url != null) {
      _runtimeUrl = url.trim();
      await prefs.setString(_prefsUrlKey, _runtimeUrl!);
    }
    if (enabledFlag != null) {
      _runtimeEnabled = enabledFlag;
      await prefs.setBool(_prefsEnabledKey, enabledFlag);
    }
    if (key != null) {
      _runtimeKey = key;
      await prefs.setString(_prefsKeyKey, key);
    }
  }

  static Future<void> clearRuntime() async {
    _runtimeUrl = null;
    _runtimeEnabled = null;
    _runtimeKey = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsUrlKey);
    await prefs.remove(_prefsEnabledKey);
    await prefs.remove(_prefsKeyKey);
  }

  /// 是否真正走 AI 网络请求。
  static bool get isEnabled {
    if (_runtimeEnabled != null) return _runtimeEnabled!;
    if (_envEnabled) return true;
    return enabled && resolvedUrl.isNotEmpty;
  }

  /// 最终请求地址：运行时 > dart-define > 代码常量。
  static String get resolvedUrl {
    final r = _runtimeUrl?.trim();
    if (r != null && r.isNotEmpty) return r;
    if (_envUrl.trim().isNotEmpty) return _envUrl.trim();
    return endpointUrl.trim();
  }

  static String get resolvedApiKey {
    final r = _runtimeKey?.trim();
    if (r != null && r.isNotEmpty) return r;
    if (_envKey.trim().isNotEmpty) return _envKey.trim();
    return apiKey.trim();
  }

  static Uri? get endpointUri {
    final u = resolvedUrl;
    if (u.isEmpty) return null;
    return Uri.tryParse(u);
  }
}
