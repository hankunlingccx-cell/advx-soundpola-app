import 'dart:convert';

import 'package:http/http.dart' as http;

class Place {
  const Place({
    required this.label,
    required this.lat,
    required this.lng,
  });

  final String label;
  final double lat;
  final double lng;
}

/// Nominatim (OpenStreetMap) geocoding. See https://nominatim.org/release-docs/latest/api/Overview/
class GeoService {
  GeoService({http.Client? client}) : _http = client ?? http.Client();

  static const _host = 'nominatim.openstreetmap.org';
  static const _headers = {
    'User-Agent': 'SoundPola/1.0',
    'Accept-Language': 'zh-CN,zh',
  };

  final http.Client _http;

  Future<List<Place>> searchPlaces(String query) async {
    final uri = Uri.https(_host, '/search', {
      'q': query,
      'format': 'jsonv2',
      'limit': '8',
      'accept-language': 'zh-CN,zh',
    });
    final res = await _http.get(uri, headers: _headers);
    if (res.statusCode != 200) {
      throw GeoException('搜索失败（${res.statusCode}）');
    }
    final list = jsonDecode(res.body);
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => Place(
              label: (m['display_name'] ?? '') as String,
              lat: double.tryParse('${m['lat']}') ?? 0,
              lng: double.tryParse('${m['lon']}') ?? 0,
            ))
        .where((p) => p.label.isNotEmpty)
        .toList();
  }

  Future<String?> reverseGeocode(double lat, double lng) async {
    final uri = Uri.https(_host, '/reverse', {
      'lat': lat.toString(),
      'lon': lng.toString(),
      'format': 'jsonv2',
      'accept-language': 'zh-CN,zh',
    });
    final res = await _http.get(uri, headers: _headers);
    if (res.statusCode != 200) return null;
    final m = jsonDecode(res.body);
    if (m is! Map<String, dynamic>) return null;
    final name = m['display_name'];
    return name is String && name.isNotEmpty ? name : null;
  }
}

class GeoException implements Exception {
  const GeoException(this.message);
  final String message;
  @override
  String toString() => message;
}
