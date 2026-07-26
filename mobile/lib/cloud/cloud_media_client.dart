import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'cloud_media_config.dart';
import 'cloud_media_models.dart';
import 'cloud_visual_package.dart';

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

  /// Upload source audio only.
  ///
  /// Protocol:
  ///   POST /api/v1/contents
  ///   Authorization: Bearer <token>
  ///   multipart/form-data — required field `audio`
  ///
  /// Visualization is uploaded separately via [uploadVideo] as MP4.
  /// Optional Indexed-MJPEG [visual] is kept for older Cloud Media deployments
  /// that still accept package fields; new servers ignore / reject them (422 →
  /// audio-only retry).
  Future<ContentCreated> uploadAudio({
    required String token,
    required File file,
    String? filename,
    CloudVisualPackage? visual,
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

    final withVisual = visual != null && visual.hasFrames;
    try {
      return await _postContent(
        token: token,
        audio: file,
        audioFilename: name,
        visual: withVisual ? visual : null,
      );
    } on CloudMediaException catch (e) {
      if (withVisual && e.statusCode == 422) {
        debugPrint(
          '[CloudMedia] visual fields rejected (422); falling back to audio-only',
        );
        return _postContent(
          token: token,
          audio: file,
          audioFilename: name,
          visual: null,
        );
      }
      rethrow;
    }
  }

  /// Upload on-device visualization MP4 after audio content exists.
  ///
  /// Protocol:
  ///   POST /api/v1/contents/{content_id}/video
  ///   multipart field `video` (e.g. visualization.mp4)
  /// Success typically returns `state=READY` + `video_sha256`.
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
          throw CloudMediaException('可视化视频上传超时（180s），请检查网络或服务状态'),
    );
    final res = await http.Response.fromStream(streamed);
    debugPrint('[CloudMedia] video upload -> ${res.statusCode} body=${res.body}');
    if (res.statusCode != 200 && res.statusCode != 201) throw _error(res);
    return ContentVideoUploaded.fromJson(_jsonMap(res.body));
  }

  Future<ContentCreated> _postContent({
    required String token,
    required File audio,
    required String audioFilename,
    CloudVisualPackage? visual,
  }) async {
    final uri = CloudMediaConfig.uri('/api/v1/contents');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $token';
    req.headers['Accept'] = 'application/json';
    // Do NOT set Content-Type manually — boundary must be included by the client.
    req.files.add(
      await http.MultipartFile.fromPath(
        'audio',
        audio.path,
        filename: audioFilename,
      ),
    );

    var visualNote = '';
    if (visual != null && visual.hasFrames) {
      Future<void> addFile(String field, File? f, String fallbackName) async {
        if (f == null || !await f.exists()) return;
        final fname = f.uri.pathSegments.isNotEmpty
            ? f.uri.pathSegments.last
            : fallbackName;
        req.files.add(
          await http.MultipartFile.fromPath(field, f.path, filename: fname),
        );
      }

      await addFile('visual', visual.mjpg, 'visual.mjpg');
      await addFile('visual_idx', visual.idx, 'visual.idx');
      await addFile(
        'visual_manifest',
        visual.manifest,
        'visual_manifest.json',
      );
      await addFile('cover', visual.cover, 'cover.jpg');
      await addFile('audio_features', visual.features, 'audio_features.bin');
      if (visual.visualSeed != null) {
        req.fields['visual_seed'] = '${visual.visualSeed}';
      }
      req.fields['renderer_version'] = visual.rendererVersion;
      visualNote =
          ' +visual package (mjpg/idx/manifest'
          '${visual.cover != null ? '/cover' : ''}'
          '${visual.features != null ? '/features' : ''})';
    }

    final audioBytes = await audio.length();
    debugPrint(
      '[CloudMedia] POST $uri multipart field=audio '
      'file=$audioFilename bytes=$audioBytes$visualNote',
    );

    final streamed = await _http.send(req).timeout(
      const Duration(seconds: 180),
      onTimeout: () => throw CloudMediaException('上传超时（180s），请检查网络或服务状态'),
    );
    final res = await http.Response.fromStream(streamed);
    debugPrint('[CloudMedia] upload -> ${res.statusCode} body=${res.body}');
    if (res.statusCode != 201) throw _error(res);
    return ContentCreated.fromJson(_jsonMap(res.body));
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

  /// Set public web title (`display_label` on `/c/{id}` page).
  ///
  /// Server defaults to「声音碎片 #XXXX」from content id; App must PATCH the
  /// user-chosen sound name after upload.
  Future<ContentSummary> renameContent({
    required String token,
    required String contentId,
    required String displayLabel,
  }) async {
    final label = displayLabel.trim();
    if (label.isEmpty) {
      throw CloudMediaException('显示名称不能为空');
    }
    final clipped = label.length > 64 ? label.substring(0, 64) : label;
    final uri = CloudMediaConfig.uri('/api/v1/contents/$contentId');
    debugPrint('[CloudMedia] PATCH $uri display_label=$clipped');
    final res = await _http.patch(
      uri,
      headers: {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'display_label': clipped}),
    );
    debugPrint('[CloudMedia] rename -> ${res.statusCode} body=${res.body}');
    if (res.statusCode != 200) throw _error(res);
    return ContentSummary.fromJson(_jsonMap(res.body));
  }

  /// Download immutable playback asset (normalized MP3 when [assetKind] is `audio`).
  ///
  /// OpenAPI marks this as PlaybackToken; owner UserToken is accepted by current
  /// Cloud Media deployments for the content owner. Writes bytes to [dest].
  Future<File> downloadAsset({
    required String token,
    required String contentId,
    required String assetKind,
    required File dest,
  }) async {
    final uri = CloudMediaConfig.uri(
      '/api/v1/contents/$contentId/assets/$assetKind',
    );
    debugPrint('[CloudMedia] GET $uri');
    final res = await _http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': '*/*',
          },
        )
        .timeout(
          const Duration(seconds: 120),
          onTimeout: () => throw CloudMediaException('下载超时（120s）'),
        );
    debugPrint(
      '[CloudMedia] asset $assetKind -> ${res.statusCode} bytes=${res.bodyBytes.length}',
    );
    if (res.statusCode != 200) throw _error(res);
    if (res.bodyBytes.isEmpty) {
      throw CloudMediaException('云端音频为空');
    }
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(res.bodyBytes, flush: true);
    return dest;
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
