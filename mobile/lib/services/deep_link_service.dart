import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:go_router/go_router.dart';
import '../router/app_routes.dart';

/// Deep link captured while the user is signed out, resumed after login.
class PendingDeepLink {
  PendingDeepLink._();

  static String? contentId;

  static bool get hasPending => contentId != null && contentId!.isNotEmpty;

  static void set(String id) => contentId = id;

  static void clear() => contentId = null;
}

/// Receives NFC/App-Link URLs (cold + warm start) and routes `/c/{id}` links
/// to the content resolver. Host is ignored on purpose so LAN-IP dev servers
/// still route correctly inside the app.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  GoRouter? _router;

  Future<void> init(GoRouter router) async {
    _router = router;
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {}
    _sub ??= _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  void _handle(Uri uri) {
    var segments = uri.pathSegments;
    if (uri.scheme != 'http' && uri.scheme != 'https' && uri.host.isNotEmpty) {
      segments = [uri.host, ...uri.pathSegments];
    }
    if (segments.length >= 2 && segments[0] == 'c') {
      final contentId = segments[1];
      if (contentId.isNotEmpty) {
        _router?.push(AppRoutes.contentPath(contentId));
      }
    }
  }
}
