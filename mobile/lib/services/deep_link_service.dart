import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/scheduler.dart';
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
///
/// Supported forms:
/// - `https://{host}/c/{contentId}` / `http://…`
/// - `soundpola://c/{contentId}` (custom scheme; AndroidManifest host=`c`)
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  GoRouter? _router;
  bool _routerReady = false;
  Uri? _pending;

  /// Extract Cloud Media content id from http(s) or `soundpola://c/{id}` URIs.
  static String? contentIdFromUri(Uri uri) {
    var segments = uri.pathSegments;
    // Custom schemes encode the first segment as host: soundpola://c/{id}
    if (uri.scheme != 'http' && uri.scheme != 'https' && uri.host.isNotEmpty) {
      segments = [uri.host, ...uri.pathSegments];
    }
    if (segments.length >= 2 && segments[0] == 'c') {
      final id = segments[1].trim();
      if (id.isNotEmpty) return id;
    }
    return null;
  }

  Future<void> init(GoRouter router) async {
    _router = router;
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {}
    _sub ??= _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  /// Call after [MaterialApp.router] is mounted so cold-start pushes land.
  void markRouterReady() {
    _routerReady = true;
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _navigate(pending);
      });
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _router = null;
    _pending = null;
    _routerReady = false;
  }

  void _handle(Uri uri) {
    if (!_routerReady) {
      _pending = uri;
      return;
    }
    _navigate(uri);
  }

  void _navigate(Uri uri) {
    final contentId = contentIdFromUri(uri);
    if (contentId == null) return;
    final target = AppRoutes.contentPath(contentId);
    final router = _router;
    if (router == null) return;
    // Prefer go so cold-start does not stack resolve on top of an error page.
    router.go(target);
  }
}
