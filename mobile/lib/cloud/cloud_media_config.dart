import 'package:shared_preferences/shared_preferences.dart';

/// Cloud Media Service base URL.
///
/// 预设固定为 `https://soundpola.babelbeast.com`。
/// 可在登录页「服务器设置」中运行时覆盖，并经 [SharedPreferences] 持久化。
class CloudMediaConfig {
  CloudMediaConfig._();

  static const _overrideKey = 'sp_cloud_base_url_override';

  static const String defaultBaseUrl = 'https://soundpola.babelbeast.com';

  static String? _override;

  /// Effective base URL: runtime override when set, otherwise preset default.
  static String get baseUrl =>
      (_override != null && _override!.isNotEmpty) ? _override! : defaultBaseUrl;

  /// True when a user-defined server address is currently active.
  static bool get hasOverride => _override != null && _override!.isNotEmpty;

  /// Public preview URLs after content is READY.
  static String previewVideoUrl(String contentId) =>
      '$baseUrl/preview/$contentId/video';

  static String previewAudioUrl(String contentId) =>
      '$baseUrl/preview/$contentId/audio';

  /// Load a persisted override. Call once during app startup.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_overrideKey);
    if (saved != null && saved.isNotEmpty) {
      _override = saved;
    }
  }

  /// Persist and activate a new base URL.
  static Future<void> save(String url) async {
    final normalized = _stripTrailingSlash(url.trim());
    _override = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_overrideKey, normalized);
  }

  /// Clear the override and fall back to [defaultBaseUrl].
  static Future<void> reset() async {
    _override = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_overrideKey);
  }

  static Uri uri(String path) {
    final root = _stripTrailingSlash(baseUrl);
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$root$p');
  }

  static String _stripTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}
