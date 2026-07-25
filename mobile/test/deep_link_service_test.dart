import 'package:flutter_test/flutter_test.dart';
import 'package:soundpola/services/deep_link_service.dart';

void main() {
  group('DeepLinkService.contentIdFromUri', () {
    test('parses https /c/{id}', () {
      final id = DeepLinkService.contentIdFromUri(
        Uri.parse('https://example.com/c/beda5cb6303848279a9cd7d761cbc374'),
      );
      expect(id, 'beda5cb6303848279a9cd7d761cbc374');
    });

    test('parses soundpola://c/{id} custom scheme', () {
      final id = DeepLinkService.contentIdFromUri(
        Uri.parse('soundpola://c/beda5cb6303848279a9cd7d761cbc374'),
      );
      expect(id, 'beda5cb6303848279a9cd7d761cbc374');
    });

    test('parses path-only /c/{id}', () {
      final id = DeepLinkService.contentIdFromUri(
        Uri.parse('/c/beda5cb6303848279a9cd7d761cbc374'),
      );
      expect(id, 'beda5cb6303848279a9cd7d761cbc374');
    });

    test('returns null for unrelated uris', () {
      expect(
        DeepLinkService.contentIdFromUri(Uri.parse('soundpola://memory/x')),
        isNull,
      );
      expect(
        DeepLinkService.contentIdFromUri(Uri.parse('https://example.com/')),
        isNull,
      );
    });
  });
}
