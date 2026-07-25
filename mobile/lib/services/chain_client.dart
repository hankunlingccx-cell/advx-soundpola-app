import 'dart:convert';
import 'package:http/http.dart' as http;
import '../cloud/cloud_media_config.dart';
import '../cloud/cloud_media_models.dart';

class ChainClient {
  ChainClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Future<ChainStatus> getChainStatus({
    required String contentId,
    required String token,
  }) async {
    final res = await _http.get(
      CloudMediaConfig.uri('/api/v1/contents/$contentId/chain'),
      headers: _authHeaders(token),
    );
    if (res.statusCode != 200) throw _error(res);
    return ChainStatus.fromJson(_jsonMap(res.body));
  }

  Future<MintResult> mintServerSide({
    required String contentId,
    required String token,
  }) async {
    final res = await _http.post(
      CloudMediaConfig.uri('/api/v1/contents/$contentId/chain/mint'),
      headers: _authHeaders(token),
    );
    if (res.statusCode != 200 && res.statusCode != 201) throw _error(res);
    return MintResult.fromJson(_jsonMap(res.body));
  }

  Future<UnsignedTx> prepareMint({
    required String contentId,
    required String token,
  }) async {
    final res = await _http.post(
      CloudMediaConfig.uri('/api/v1/contents/$contentId/chain/prepare-mint'),
      headers: _authHeaders(token),
    );
    if (res.statusCode != 200) throw _error(res);
    return UnsignedTx.fromJson(_jsonMap(res.body));
  }

  Future<MintResult> submitSigned({
    required String contentId,
    required String rawTx,
    required String token,
  }) async {
    final res = await _http.post(
      CloudMediaConfig.uri('/api/v1/contents/$contentId/chain/submit-signed'),
      headers: _authHeaders(token),
      body: jsonEncode({'raw_tx': rawTx}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) throw _error(res);
    return MintResult.fromJson(_jsonMap(res.body));
  }

  Future<MintResult> claimServerSide({
    required String contentId,
    required String token,
  }) async {
    final res = await _http.post(
      CloudMediaConfig.uri('/api/v1/contents/$contentId/claim'),
      headers: _authHeaders(token),
    );
    if (res.statusCode != 200 && res.statusCode != 201) throw _error(res);
    return MintResult.fromJson(_jsonMap(res.body));
  }

  Future<UnsignedTx> prepareClaim({
    required String contentId,
    required String token,
  }) async {
    final res = await _http.post(
      CloudMediaConfig.uri('/api/v1/contents/$contentId/claim/prepare'),
      headers: _authHeaders(token),
    );
    if (res.statusCode != 200) throw _error(res);
    return UnsignedTx.fromJson(_jsonMap(res.body));
  }

  Future<MintResult> submitClaimSigned({
    required String contentId,
    required String rawTx,
    required String token,
  }) async {
    final res = await _http.post(
      CloudMediaConfig.uri('/api/v1/contents/$contentId/claim/submit-signed'),
      headers: _authHeaders(token),
      body: jsonEncode({'raw_tx': rawTx}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) throw _error(res);
    return MintResult.fromJson(_jsonMap(res.body));
  }

  Future<EditionsList> getEditions({
    required String contentId,
    required String token,
  }) async {
    final res = await _http.get(
      CloudMediaConfig.uri('/api/v1/contents/$contentId/editions'),
      headers: _authHeaders(token),
    );
    if (res.statusCode != 200) throw _error(res);
    return EditionsList.fromJson(_jsonMap(res.body));
  }

  Map<String, dynamic> _jsonMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw CloudMediaException('无效的 JSON 响应');
  }

  CloudMediaException _error(http.Response res) {
    String detail = '链上请求失败 (${res.statusCode})';
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
