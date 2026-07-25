import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// 录音时捕获 GPS 地点文案（反查地名；失败则回退坐标或「地点未记录」）。
class LocationCaptureService {
  LocationCaptureService._();

  static const unsetLabel = '地点未记录';

  /// 请求权限并读取当前位置，返回可展示的地点字符串。
  static Future<String> capturePlaceLabel() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return unsetLabel;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return unsetLabel;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );

      try {
        final marks = await Geocoding().placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (marks.isNotEmpty) {
          final label = _formatPlacemark(marks.first);
          if (label.isNotEmpty) return label;
        }
      } catch (_) {
        // 反查失败时回退坐标
      }

      return '${pos.latitude.toStringAsFixed(4)}, '
          '${pos.longitude.toStringAsFixed(4)}';
    } catch (_) {
      return unsetLabel;
    }
  }

  static String _formatPlacemark(Placemark p) {
    final city = (p.locality?.trim().isNotEmpty == true)
        ? p.locality!.trim()
        : (p.subAdministrativeArea?.trim().isNotEmpty == true)
            ? p.subAdministrativeArea!.trim()
            : (p.administrativeArea?.trim() ?? '');
    final spot = (p.subLocality?.trim().isNotEmpty == true)
        ? p.subLocality!.trim()
        : (p.name?.trim().isNotEmpty == true &&
                p.name != city &&
                p.name != p.street)
            ? p.name!.trim()
            : (p.thoroughfare?.trim() ?? '');

    if (city.isNotEmpty && spot.isNotEmpty && spot != city) {
      return '$city · $spot';
    }
    if (city.isNotEmpty) return city;
    if (spot.isNotEmpty) return spot;
    final country = p.country?.trim() ?? '';
    return country;
  }
}
