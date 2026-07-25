import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../cloud/cloud_media_client.dart';
import '../data/session.dart';
import '../device/device_models.dart';
import '../device/device_registry.dart';
import '../router/app_routes.dart';
import '../visual/audio_feature_timeline.dart';
import 'auth_service.dart';
import 'permission_service.dart';

class RingDeviceInfo {
  const RingDeviceInfo({
    required this.address,
    required this.firmwareVersion,
    required this.model,
    required this.batteryPercent,
    required this.batteryCharging,
    required this.audioCount,
    required this.serialNumber,
    required this.cpuid,
  });

  final String address;
  final String firmwareVersion;
  final String model;
  final int? batteryPercent;
  final bool batteryCharging;
  final int? audioCount;
  final String serialNumber;
  final String cpuid;

  factory RingDeviceInfo.fromMap(Map<dynamic, dynamic> map) {
    return RingDeviceInfo(
      address: map['address'] as String? ?? RingRecordingService.ringAddress,
      firmwareVersion: map['firmwareVersion'] as String? ?? '—',
      model: map['model'] as String? ?? 'Ring Sound',
      batteryPercent: (map['batteryPercent'] as num?)?.toInt(),
      batteryCharging: map['batteryCharging'] as bool? ?? false,
      audioCount: (map['audioCount'] as num?)?.toInt(),
      serialNumber: map['serialNumber'] as String? ?? '',
      cpuid: map['cpuid'] as String? ?? '',
    );
  }
}

class RingRecordingCapture {
  const RingRecordingCapture({
    required this.fileIndex,
    required this.rawPath,
    required this.uploadPath,
    required this.durationSec,
    required this.byteLength,
    required this.packetCount,
  });

  final int fileIndex;
  final String rawPath;
  final String uploadPath;
  final int durationSec;
  final int byteLength;
  final int packetCount;

  String get filename {
    final segments = Uri.file(uploadPath).pathSegments;
    return segments.isEmpty ? 'ring-recording.ogg' : segments.last;
  }

  factory RingRecordingCapture.fromMap(Map<dynamic, dynamic> map) {
    return RingRecordingCapture(
      fileIndex: (map['fileIndex'] as num?)?.toInt() ?? 0,
      rawPath: map['rawPath'] as String? ?? '',
      uploadPath: map['uploadPath'] as String? ?? '',
      durationSec: (map['durationSec'] as num?)?.toInt() ?? 1,
      byteLength: (map['byteLength'] as num?)?.toInt() ?? 0,
      packetCount: (map['packetCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Keeps the ring armed while the app is open and the user is logged in.
///
/// The ring still controls record start/stop with its physical button. This
/// service keeps a BLE session ready, receives the saved Speex recording after
/// the user releases the button, uploads the Ogg Speex file, then opens the
/// existing recording result screen.
class RingRecordingService {
  RingRecordingService._();
  static final RingRecordingService instance = RingRecordingService._();

  static const _channel = MethodChannel('soundpola/ring_sound');
  static const ringAddress = 'CB:AF:A4:D0:6B:A5';
  static const _scanTimeoutMs = 120000;
  static const _waitTimeoutMs = 900000;
  static const _commandTimeoutMs = 25000;

  GoRouter? _router;
  bool _running = false;
  bool _looping = false;

  bool get isRunning => _running;

  void start(GoRouter router) {
    _router = router;
    if (_running) return;
    _running = true;
    unawaited(_runLoop());
  }

  void stop() {
    _running = false;
    unawaited(_cancelBridge());
  }

  Future<SoundPolaDevice> pairRing({String address = ringAddress}) async {
    final permitted = await PermissionService.ensureRingBluetooth();
    if (!permitted) {
      throw StateError('需要蓝牙权限才能连接指环');
    }

    final wasRunning = _running;
    final router = _router;
    _running = false;
    await _cancelBridge();
    try {
      final info = await connectRing(address: address);
      final device = SoundPolaDevice(
        deviceId: ringDeviceId(address),
        deviceName: 'SoundPola Ring',
        model: info.model.isEmpty ? 'Ring Sound' : info.model,
        firmwareVersion: info.firmwareVersion,
        bindingStatus: DeviceBindingStatus.bound,
        lastConnectedAt: DateTime.now(),
        batteryLevel: info.batteryPercent,
        supportedCapabilities: const [
          'ring_record',
          'ble_audio',
          'motion_capture',
        ],
        ownerAccountId: AuthService.instance.cloudUserId,
      );
      await DeviceRegistry.instance.upsert(device);
      return device;
    } finally {
      if (wasRunning && router != null) {
        start(router);
      }
    }
  }

  Future<RingDeviceInfo> connectRing({String address = ringAddress}) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'connectRing',
      {'address': address, 'scanTimeoutMs': 25000, 'commandTimeoutMs': 10000},
    );
    if (raw == null) {
      throw StateError('Ring bridge returned no device info.');
    }
    return RingDeviceInfo.fromMap(raw);
  }

  static String ringDeviceId(String address) =>
      'ring_${address.replaceAll(':', '').toUpperCase()}';

  Future<void> _cancelBridge() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (_) {}
  }

  Future<void> _runLoop() async {
    if (_looping) return;
    _looping = true;
    try {
      while (_running) {
        if (!AuthService.instance.isLoggedIn) {
          await _delay(const Duration(seconds: 2));
          continue;
        }

        final permitted = await PermissionService.ensureRingBluetooth();
        if (!permitted) {
          debugPrint('[RingRecording] Bluetooth permission not granted.');
          await _delay(const Duration(seconds: 30));
          continue;
        }

        try {
          final capture = await _receiveNext();
          if (!_running) break;
          await _uploadAndOpenResult(capture);
        } on MissingPluginException {
          debugPrint('[RingRecording] Platform ring bridge is unavailable.');
          await _delay(const Duration(minutes: 5));
        } on PlatformException catch (error) {
          debugPrint('[RingRecording] ${error.code}: ${error.message}');
          await _delay(const Duration(seconds: 8));
        } catch (error) {
          debugPrint('[RingRecording] $error');
          await _delay(const Duration(seconds: 8));
        }
      }
    } finally {
      _looping = false;
    }
  }

  Future<RingRecordingCapture> _receiveNext() async {
    final raw = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('receiveNextRecording', {
          'address': ringAddress,
          'scanTimeoutMs': _scanTimeoutMs,
          'waitTimeoutMs': _waitTimeoutMs,
          'commandTimeoutMs': _commandTimeoutMs,
        });
    if (raw == null) {
      throw StateError('Ring bridge returned no recording.');
    }
    final capture = RingRecordingCapture.fromMap(raw);
    if (capture.uploadPath.isEmpty || !File(capture.uploadPath).existsSync()) {
      throw StateError('Ring recording file is missing.');
    }
    return capture;
  }

  Future<void> _uploadAndOpenResult(RingRecordingCapture capture) async {
    final router = _router;
    if (router == null) return;

    String? contentId;
    String? cloudState;
    String? uploadError;
    final cloud = CloudMediaClient();
    try {
      final token = await AuthService.instance.requireCloudToken();
      final created = await cloud.uploadAudio(
        token: token,
        file: File(capture.uploadPath),
        filename: capture.filename,
      );
      contentId = created.contentId;
      cloudState = created.state.wire;
    } catch (error) {
      uploadError = error.toString();
      debugPrint('[RingRecording] upload failed: $uploadError');
    } finally {
      cloud.close();
    }

    final seed = DateTime.now().millisecondsSinceEpoch % 900000 + 1000;
    RecordingSession.set(
      path: capture.uploadPath,
      duration: capture.durationSec,
      seed: seed,
      timeline: AudioFeatureTimeline(),
      imported: true,
      ring: true,
      titleHint: '指环录音 #${capture.fileIndex}',
      cloudContentId: contentId,
      cloudState: cloudState,
      cloudUploadError: uploadError,
    );
    router.push(AppRoutes.resultPath(capture.durationSec));
  }

  Future<void> _delay(Duration duration) async {
    final end = DateTime.now().add(duration);
    while (_running && DateTime.now().isBefore(end)) {
      final remaining = end.difference(DateTime.now());
      await Future<void>.delayed(
        remaining > const Duration(milliseconds: 500)
            ? const Duration(milliseconds: 500)
            : remaining,
      );
    }
  }
}
