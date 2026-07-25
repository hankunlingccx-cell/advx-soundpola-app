import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'cloud_media_config.dart';
import 'cloud_media_models.dart';

/// AdventureX Cloud Media API client (UserToken scope only).
class CloudMediaClient {
  CloudMediaClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  static const _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Register a new account. Backend: POST /api/v1/users.
  Future<EmailRegistered> register({
    required String email,
    required String password,
    bool storePrivateKey = false,
  }) async {
    final res = await _http.post(
      CloudMediaConfig.uri('/api/v1/users'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'email': email,
        'password': password,
        'store_private_key': storePrivateKey,
      }),
    );
    if (res.statusCode != 201) throw _error(res);
    return EmailRegistered.fromJson(_jsonMap(res.body));
  }

  /// Log in with email + password. Backend: POST /api/v1/sessions.
  Future<UserTokenIssued> login({
    required String email,
    required String password,
  }) async {
    final res = await _http.post(
      CloudMediaConfig.uri('/api/v1/sessions'),
      headers: _jsonHeaders,
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (res.statusCode != 201) throw _error(res);
    return UserTokenIssued.fromJson(_jsonMap(res.body));
  }

  /// Anonymous / device token. Backend: POST /api/v1/users/tokens.
  Future<UserTokenIssued> issueUserToken() async {
    final uri = CloudMediaConfig.uri('/api/v1/users/tokens');
    debugPrint('[CloudMedia] POST $uri');
    final res = await _http.post(uri);
    debugPrint('[CloudMedia] token -> ${res.statusCode}');
    if (res.statusCode != 201) {
      throw _error(res);
    }
    return UserTokenIssued.fromJson(_jsonMap(res.body));
  }

  /// Fetch the current account profile. Backend: GET /api/v1/users/me.
  Future<UserProfile> getMe(String token) async {
    final res = await _http.get(
      CloudMediaConfig.uri('/api/v1/users/me'),
      headers: _authHeaders(token),
    );
    if (res.statusCode != 200) throw _error(res);
    return UserProfile.fromJson(_jsonMap(res.body));
  }

  Future<ContentList> listContents(String token) async {
    final uri = CloudMediaConfig.uri('/api/v1/contents');
    debugPrint('[CloudMedia] GET $uri');
    final res = await _http.get(uri, headers: _authHeaders(token));
    debugPrint('[CloudMedia] list -> ${res.statusCode}');
    if (res.statusCode != 200) throw _error(res);
    return ContentList.fromJson(_jsonMap(res.body));
  }

  /// Step 1: upload source audio.
  ///
  /// `POST /api/v1/contents` multipart field `audio`.
  Future<ContentCreated> uploadAudio({
    required String token,
    required File file,
    String? filename,
  }) async {
    final length = await file.length();
    if (length <= 0) {
      throw CloudMediaException('音频文件为空，无法上传');
    }
    if (length > 50 * 1024 * 1024) {
      throw CloudMediaException('音频超过 50 MiB 上限', statusCode: 413);
    }

    final name = (filename != null && filename.isNotEmpty)
        ? filename
        : file.uri.pathSegments.isNotEmpty
            ? file.uri.pathSegments.last
            : 'recording.wav';

    final uri = CloudMediaConfig.uri('/api/v1/contents');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $token';
    req.headers['Accept'] = 'application/json';
    req.files.add(
      await http.MultipartFile.fromPath(
        'audio',
        file.path,
        filename: name,
      ),
    );

    debugPrint(
      '[CloudMedia] POST $uri multipart field=audio '
      'file=$name bytes=$length',
    );

    final streamed = await _http.send(req).timeout(
      const Duration(seconds: 180),
      onTimeout: () => throw CloudMediaException('上传超时（180s），请检查网络或服务状态'),
    );
    final res = await http.Response.fromStream(streamed);
    debugPrint(
      '[CloudMedia] upload audio -> ${res.statusCode} body=${res.body}',
    );
    if (res.statusCode != 201) throw _error(res);
    return ContentCreated.fromJson(_jsonMap(res.body));
  }

  /// Step 2: upload on-device visualization MP4.
  ///
  /// `POST /api/v1/contents/{contentId}/video` multipart field `video`.
  /// Success typically returns `state: READY`.
  Future<ContentVideoUploaded> uploadVideo({
    required String token,
    required String contentId,
    required File file,
    String filename = 'visualization.mp4',
  }) async {
    final length = await file.length();
    if (length <= 0) {
      throw CloudMediaException('可视化视频为空，无法上传');
    }
    if (length > 100 * 1024 * 1024) {
      throw CloudMediaException('可视化视频超过 100 MiB 上限', statusCode: 413);
    }

    final uri = CloudMediaConfig.uri('/api/v1/contents/$contentId/video');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $token';
    req.headers['Accept'] = 'application/json';
    req.files.add(
      await http.MultipartFile.fromPath(
        'video',
        file.path,
        filename: filename,
      ),
    );

    debugPrint(
      '[CloudMedia] POST $uri multipart field=video '
      'file=$filename bytes=$length',
    );

    final streamed = await _http.send(req).timeout(
      const Duration(seconds: 180),
      onTimeout: () =>
          throw CloudMediaException('视频上传超时（180s），请检查网络或服务状态'),
    );
    final res = await http.Response.fromStream(streamed);
    debugPrint(
      '[CloudMedia] upload video -> ${res.statusCode} body=${res.body}',
    );
    if (res.statusCode != 200 && res.statusCode != 201) throw _error(res);
    return ContentVideoUploaded.fromJson(_jsonMap(res.body));
  }

  Future<ContentSummary> getContent({
    required String token,
    required String contentId,
  }) async {
    final uri = CloudMediaConfig.uri('/api/v1/contents/$contentId');
    final res = await _http.get(uri, headers: _authHeaders(token));
    if (res.statusCode != 200) throw _error(res);
    return ContentSummary.fromJson(_jsonMap(res.body));
  }

  Future<ContentSummary> retryContent({
    required String token,
    required String contentId,
  }) async {
    final uri = CloudMediaConfig.uri('/api/v1/contents/$contentId/retry');
    debugPrint('[CloudMedia] POST $uri');
    final res = await _http.post(uri, headers: _authHeaders(token));
    debugPrint('[CloudMedia] retry -> ${res.statusCode}');
    if (res.statusCode != 202 && res.statusCode != 200) throw _error(res);
    return ContentSummary.fromJson(_jsonMap(res.body));
  }

  Future<void> deleteContent({
    required String token,
    required String contentId,
  }) async {
    final res = await _http.delete(
      CloudMediaConfig.uri('/api/v1/contents/$contentId'),
      headers: _authHeaders(token),
    );
    if (res.statusCode != 200 && res.statusCode != 204) throw _error(res);
  }

  /// Preflight: process must be alive. ready=503 only warns — upload can still
  /// return 201 UPLOADED; processing may fail later if worker/FFmpeg is down.
  Future<void> assertReachable() async {
    final health = await _http
        .get(CloudMediaConfig.uri('/api/v1/health'))
        .timeout(const Duration(seconds: 10));
    debugPrint('[CloudMedia] health -> ${health.statusCode} ${health.body}');
    if (health.statusCode != 200) {
      throw CloudMediaException('云服务不可用 (health ${health.statusCode})');
    }
    try {
      final ready = await _http
          .get(CloudMediaConfig.uri('/api/v1/ready'))
          .timeout(const Duration(seconds: 15));
      debugPrint('[CloudMedia] ready -> ${ready.statusCode} ${ready.body}');
      if (ready.statusCode == 503) {
        debugPrint(
          '[CloudMedia] warning: ready=503 (worker/FFmpeg may be down); '
          'still attempting upload',
        );
      }
    } catch (e) {
      debugPrint('[CloudMedia] ready check skipped: $e');
    }
  }

  /// Poll until READY / FAILED / DELETED or [timeout].
  Future<ContentSummary> waitUntilReady({
    required String token,
    required String contentId,
    Duration timeout = const Duration(minutes: 3),
    void Function(ContentSummary summary)? onUpdate,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var delay = const Duration(milliseconds: 800);
    while (DateTime.now().isBefore(deadline)) {
      final summary = await getContent(token: token, contentId: contentId);
      debugPrint('[CloudMedia] poll $contentId -> ${summary.state.wire}');
      onUpdate?.call(summary);
      if (summary.state == CloudContentState.ready) return summary;
      if (summary.state == CloudContentState.failed) {
        throw CloudMediaException(
          summary.errorMessage ?? '云端处理失败（${summary.errorCode ?? 'FAILED'}）',
        );
      }
      if (summary.state == CloudContentState.deleted) {
        throw CloudMediaException('内容已被撤销');
      }
      await Future.delayed(delay);
      if (delay < const Duration(seconds: 4)) {
        delay = Duration(milliseconds: (delay.inMilliseconds * 1.4).round());
      }
    }
    throw CloudMediaException('云端处理超时，请稍后在 Collection 查看状态');
  }

  Map<String, dynamic> _jsonMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw CloudMediaException('无效的 JSON 响应');
  }

  CloudMediaException _error(http.Response res) {
    String detail = '请求失败 (${res.statusCode})';
    try {
      final map = _jsonMap(res.body);
      final d = map['detail'];
      if (d is String && d.isNotEmpty) {
        detail = d;
      } else if (d is List && d.isNotEmpty) {
        detail = d.first.toString();
      }
    } catch (_) {
      if (res.body.isNotEmpty) detail = '$detail ${res.body}';
    }
    return CloudMediaException(detail, statusCode: res.statusCode);
  }

  void close() => _http.close();
}
