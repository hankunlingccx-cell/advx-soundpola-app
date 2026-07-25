import 'package:shared_preferences/shared_preferences.dart';

/// Cloud Media Service base URL.
///
/// Compile-time default via:
/// `flutter run --dart-define=CLOUD_MEDIA_BASE=http://192.168.1.10:9000`
///
/// May be overridden at runtime from the in-app server settings screen; the
/// override is persisted with [SharedPreferences] and takes precedence.
class CloudMediaConfig {
  CloudMediaConfig._();

  static const _overrideKey = 'sp_cloud_base_url_override';

  static const defaultBaseUrl = String.fromEnvironment(
    'CLOUD_MEDIA_BASE',
    defaultValue: 'http://127.0.0.1:9000',
  );

  static String? _override;

  /// Effective base URL: runtime override when set, otherwise compile default.
  static String get baseUrl =>
      (_override != null && _override!.isNotEmpty) ? _override! : defaultBaseUrl;

  /// True when a user-defined server address is currently active.
  static bool get hasOverride => _override != null && _override!.isNotEmpty;

  /// Load a persisted override. Call once during app startup.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_overrideKey);
    if (saved != null && saved.isNotEmpty) {
      _override = saved;
    }
  }

  /// Persist and activate a new base URL (e.g. `http://192.168.1.10:9000`).
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
