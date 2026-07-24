/// Cloud Media Service base URL.
///
/// Override at build/run time:
/// `flutter run --dart-define=CLOUD_MEDIA_BASE=https://advx26.babelbeast.com`
class CloudMediaConfig {
  CloudMediaConfig._();

  static const baseUrl = String.fromEnvironment(
    'CLOUD_MEDIA_BASE',
    defaultValue: 'https://advx26.babelbeast.com',
  );

  static Uri uri(String path) {
    final root = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$root$p');
  }
}
