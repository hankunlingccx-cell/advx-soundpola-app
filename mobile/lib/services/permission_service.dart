import 'dart:io';

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

  static Future<bool> ensureRingBluetooth() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    if (Platform.isIOS) {
      var bluetooth = await Permission.bluetooth.status;
      if (!bluetooth.isGranted) {
        bluetooth = await Permission.bluetooth.request();
      }
      return bluetooth.isGranted;
    }

    var scan = await Permission.bluetoothScan.status;
    if (!scan.isGranted) scan = await Permission.bluetoothScan.request();

    var connect = await Permission.bluetoothConnect.status;
    if (!connect.isGranted) {
      connect = await Permission.bluetoothConnect.request();
    }

    if (scan.isGranted && connect.isGranted) return true;

    var location = await Permission.location.status;
    if (!location.isGranted) location = await Permission.location.request();
    return location.isGranted &&
        (scan.isGranted || scan.isLimited) &&
        (connect.isGranted || connect.isLimited);
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
