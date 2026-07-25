import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../cloud/cloud_media_config.dart';
import '../widgets/visual_shape.dart';

/// Fetches and caches cloud 3D visual JSON.
///
/// - [cacheFromUrl]: mint-time path — fetch, validate, persist to
///   `<appDocs>/visuals/vis_<contentId>.json`, return the local path (null on
///   any failure; non-blocking for callers).
/// - [load]: lazy path — async-load a cached file into the in-memory cache.
/// - [peek]: sync read of the in-memory cache; returns null when not yet
///   loaded so callers' build() falls back to seed rendering.
class VisualShapeService {
  VisualShapeService._();
  static final VisualShapeService instance = VisualShapeService._();

  final http.Client _http = http.Client();
  final _cache = <String, SoundVisualShape>{}; // key = visualPath
  final _loading = <String, Future<SoundVisualShape?>>{};

  Future<String> _visualsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final v = Directory('${dir.path}/visuals');
    if (!await v.exists()) await v.create(recursive: true);
    return v.path;
  }

  /// Fetch the visual JSON from [url], validate, persist to
  /// `<appDocs>/visuals/vis_<contentId>.json`. Returns the local path on
  /// success, null on any failure. Non-blocking: callers should not abort
  /// minting on a null result.
  Future<String?> cacheFromUrl({
    required String contentId,
    required String url,
    String? token,
  }) async {
    try {
      final headers =
          (token != null && _isCloudHost(url)) ? _authHeaders(token) : null;
      final res = await _http.get(Uri.parse(url), headers: headers);
      if (res.statusCode != 200) return null;
      final body = res.body;
      final shape =
          SoundVisualShape.fromJson(jsonDecode(body) as Map<String, dynamic>);
      final dir = await _visualsDir();
      final path = '$dir/vis_$contentId.json';
      await File(path).writeAsString(body);
      _cache[path] = shape;
      return path;
    } catch (e) {
      debugPrint('VisualShapeService.cacheFromUrl failed: $e');
      return null;
    }
  }

  /// Async-load a cached visual file into the in-memory cache. Returns null
  /// if [visualPath] is null, or the file is missing/invalid.
  Future<SoundVisualShape?> load(String? visualPath) async {
    if (visualPath == null) return null;
    if (_cache.containsKey(visualPath)) return _cache[visualPath]!;
    if (_loading.containsKey(visualPath)) return _loading[visualPath]!;
    final fut =
        Future<SoundVisualShape?>.value(SoundVisualShape.fromFile(visualPath));
    _loading[visualPath] = fut;
    return fut.then((s) {
      if (s != null) _cache[visualPath] = s;
      _loading.remove(visualPath);
      return s;
    });
  }

  /// Sync peek of the in-memory cache. Use from build(); returns null when
  /// the shape is not yet loaded so the canvas falls back to seed rendering.
  SoundVisualShape? peek(String? visualPath) =>
      visualPath == null ? null : _cache[visualPath];

  bool _isCloudHost(String url) {
    try {
      final host = Uri.parse(url).host;
      final cloudHost = Uri.parse(CloudMediaConfig.baseUrl).host;
      return host.isNotEmpty && host == cloudHost;
    } catch (_) {
      return false;
    }
  }

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  void dispose() {
    _http.close();
  }
}
