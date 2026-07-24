/// Cloud Media Service base URL.
///
/// Override at build/run time:
/// `flutter run --dart-define=CLOUD_MEDIA_BASE=http://192.168.1.10:9000`
class CloudMediaConfig {
  CloudMediaConfig._();

  static const baseUrl = String.fromEnvironment(
    'CLOUD_MEDIA_BASE',
    defaultValue: 'http://127.0.0.1:9000',
  );

  static Uri uri(String path) {
    final root = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$root$p');
  }
}
