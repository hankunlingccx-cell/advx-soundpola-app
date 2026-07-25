import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  PermissionService._();

  static Future<bool> ensureMicrophone() async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return true;
    status = await Permission.microphone.request();
    return status.isGranted;
  }

  static Future<bool> ensureLocation() async {
    var status = await Permission.location.status;
    if (status.isGranted) return true;
    status = await Permission.location.request();
    return status.isGranted;
  }

  static Future<bool> ensureCamera() async {
    var status = await Permission.camera.status;
    if (status.isGranted) return true;
    status = await Permission.camera.request();
    return status.isGranted;
  }

  static Future<bool> isMicrophoneGranted() async {
    return Permission.microphone.isGranted;
  }

  static Future<void> openSettings() => openAppSettings();
}
