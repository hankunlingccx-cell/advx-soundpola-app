import 'dart:convert';
import 'dart:io';
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
    final res = await _http.get(
      CloudMediaConfig.uri('/api/v1/contents'),
      headers: _authHeaders(token),
    );
    if (res.statusCode != 200) throw _error(res);
    return ContentList.fromJson(_jsonMap(res.body));
  }

  Future<ContentCreated> uploadAudio({
    required String token,
    required File file,
    String filename = 'recording.m4a',
  }) async {
    final length = await file.length();
    if (length > 50 * 1024 * 1024) {
      throw CloudMediaException('音频超过 50 MiB 上限', statusCode: 413);
    }
    final req = http.MultipartRequest(
      'POST',
      CloudMediaConfig.uri('/api/v1/contents'),
    );
    req.headers.addAll(_authHeaders(token));
    req.files.add(
      await http.MultipartFile.fromPath(
        'audio',
        file.path,
        filename: filename,
      ),
    );
    final streamed = await _http.send(req);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 201) throw _error(res);
    return ContentCreated.fromJson(_jsonMap(res.body));
  }

  Future<ContentSummary> getContent({
    required String token,
    required String contentId,
  }) async {
    final res = await _http.get(
      CloudMediaConfig.uri('/api/v1/contents/$contentId'),
      headers: _authHeaders(token),
    );
    if (res.statusCode != 200) throw _error(res);
    return ContentSummary.fromJson(_jsonMap(res.body));
  }

  Future<ContentSummary> retryContent({
    required String token,
    required String contentId,
  }) async {
    final res = await _http.post(
      CloudMediaConfig.uri('/api/v1/contents/$contentId/retry'),
      headers: _authHeaders(token),
    );
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
    } catch (_) {}
    return CloudMediaException(detail, statusCode: res.statusCode);
  }

  void close() => _http.close();
}
