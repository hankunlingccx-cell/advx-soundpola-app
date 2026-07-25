import 'package:shared_preferences/shared_preferences.dart';

/// ──────────────────────────────────────────────────────────────
/// ★ AI 节拍 API 链接配置（接模型服务只改这里）
/// ──────────────────────────────────────────────────────────────
///
/// 用法：
/// 1. 把 [endpointUrl] 改成你的 AI 接口完整地址，例如：
///    `https://your-ai.example.com/v1/soundpola/beat-plan`
/// 2. 将 [enabled] 设为 `true`
/// 3. （可选）填 [apiKey]，会以 `Authorization: Bearer …` 发送
///
/// 也可运行时覆盖（SharedPreferences），或：
/// `flutter run --dart-define=BEAT_AI_API_URL=https://…`
/// `flutter run --dart-define=BEAT_AI_API_ENABLED=true`
///
/// 请求：POST JSON = FeatureSummary + seed（不含完整音频）
/// 响应：BeatPlan JSON（events 含 timeMs / sourceIndex / playDurationMs …）
/// 失败时自动回退本地随机轮播算法。
class BeatAiApiConfig {
  BeatAiApiConfig._();

  // ─── 在此填写 AI API 链接 ───────────────────────────────────
  /// 例如：'https://api.example.com/v1/lab/beat-plan'
  /// 留空且 enabled=false 时走本地随机生成。
  static const String endpointUrl = '';

  /// 设为 true 后才会请求上方 URL。
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
