import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_media_client.dart';
import '../data/session.dart';
import '../device/device_models.dart';
import '../device/device_registry.dart';
import '../router/app_routes.dart';
import '../visual/audio_feature_timeline.dart';
import 'auth_service.dart';
import 'permission_service.dart';

class RingScanDevice {
  const RingScanDevice({
    required this.name,
    required this.address,
    this.rssi,
  });

  final String name;
  final String address;
  final int? rssi;

  factory RingScanDevice.fromMap(Map<dynamic, dynamic> map) {
    return RingScanDevice(
      name: (map['name'] as String?)?.trim().isNotEmpty == true
          ? (map['name'] as String).trim()
          : 'ring',
      address: map['address'] as String? ?? '',
      rssi: (map['rssi'] as num?)?.toInt(),
    );
  }
}

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
      address: map['address'] as String? ?? '',
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
    this.playPath = '',
    this.oggPath = '',
  });

  final int fileIndex;
  final String rawPath;
  final String uploadPath;
  final String playPath;
  final String oggPath;
  final int durationSec;
  final int byteLength;
  final int packetCount;

  /// Local path used for preview / Draft packaging (WAV when available).
  String get localAudioPath {
    if (playPath.isNotEmpty) return playPath;
    return uploadPath;
  }

  String get filename {
    final path = localAudioPath;
    final segments = Uri.file(path).pathSegments;
    return segments.isEmpty ? 'ring-recording.wav' : segments.last;
  }

  factory RingRecordingCapture.fromMap(Map<dynamic, dynamic> map) {
    final upload = map['uploadPath'] as String? ?? '';
    final play = map['playPath'] as String? ?? '';
    return RingRecordingCapture(
      fileIndex: (map['fileIndex'] as num?)?.toInt() ?? 0,
      rawPath: map['rawPath'] as String? ?? '',
      uploadPath: upload,
      playPath: play.isNotEmpty ? play : upload,
      oggPath: map['oggPath'] as String? ?? '',
      durationSec: (map['durationSec'] as num?)?.toInt() ?? 1,
      byteLength: (map['byteLength'] as num?)?.toInt() ?? 0,
      packetCount: (map['packetCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Keeps the paired ring armed while the app is open and the user is logged in.
///
/// The ring controls record start/stop with its physical button. After pairing,
/// this service keeps a BLE session ready, receives the Speex recording when
/// the user finishes, decodes to WAV on device, uploads, then opens the
/// existing result screen (no phone mic recording flow).
class RingRecordingService {
  RingRecordingService._();
  static final RingRecordingService instance = RingRecordingService._();

  static const _channel = MethodChannel('soundpola/ring_sound');
  static const _prefsAddressKey = 'soundpola_ring_ble_address_v1';
  static const _prefsNameKey = 'soundpola_ring_ble_name_v1';
  static const kNamePrefix = 'ring';
  static const _scanTimeoutMs = 120000;
  static const _waitTimeoutMs = 900000;
  static const _commandTimeoutMs = 25000;

  GoRouter? _router;
  bool _running = false;
  bool _looping = false;
  String? _pairedAddress;
  String? _pairedName;
  bool _prefsLoaded = false;

  bool get isRunning => _running;
  String? get pairedAddress => _pairedAddress;
  String? get pairedName => _pairedName;
  bool get hasPairedRing =>
      _pairedAddress != null && _pairedAddress!.isNotEmpty;

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

  Future<void> _ensurePrefs() async {
    if (_prefsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _pairedAddress = prefs.getString(_prefsAddressKey);
    _pairedName = prefs.getString(_prefsNameKey);
    _prefsLoaded = true;
  }

  Future<void> _persistPair({
    required String address,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsAddressKey, address);
    await prefs.setString(_prefsNameKey, name);
    _pairedAddress = address;
    _pairedName = name;
    _prefsLoaded = true;
  }

  /// BLE scan; only devices whose advertised name starts with [namePrefix]
  /// (case-insensitive) are returned.
  Future<List<RingScanDevice>> scanRings({
    int durationMs = 8000,
    String namePrefix = kNamePrefix,
  }) async {
    final permitted = await PermissionService.ensureRingBluetooth();
    if (!permitted) {
      throw StateError('需要蓝牙权限才能扫描指环');
    }

    final raw = await _channel.invokeMethod<List<dynamic>>('scanRings', {
      'durationMs': durationMs,
      'namePrefix': namePrefix,
    });
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map((e) => RingScanDevice.fromMap(e))
        .where((d) => d.address.isNotEmpty)
        .where((d) => d.name.toLowerCase().startsWith(namePrefix.toLowerCase()))
        .toList();
  }

  Future<SoundPolaDevice> pairRing({
    required String address,
    String? displayName,
  }) async {
    final permitted = await PermissionService.ensureRingBluetooth();
    if (!permitted) {
      throw StateError('需要蓝牙权限才能连接指环');
    }
    if (address.trim().isEmpty) {
      throw StateError('无效的指环地址');
    }

    final wasRunning = _running;
    final router = _router;
    _running = false;
    await _cancelBridge();
    try {
      final info = await connectRing(address: address);
      final name = (displayName != null && displayName.trim().isNotEmpty)
          ? displayName.trim()
          : (info.model.isNotEmpty ? info.model : 'SoundPola Ring');
      await _persistPair(address: info.address.isNotEmpty ? info.address : address, name: name);

      final device = SoundPolaDevice(
        deviceId: ringDeviceId(_pairedAddress!),
        deviceName: name,
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

  Future<RingDeviceInfo> connectRing({required String address}) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'connectRing',
      {
        'address': address,
        'scanTimeoutMs': 25000,
        'commandTimeoutMs': 10000,
      },
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

        await _ensurePrefs();
        final address = _pairedAddress;
        if (address == null || address.isEmpty) {
          await _delay(const Duration(seconds: 5));
          continue;
        }

        final permitted = await PermissionService.ensureRingBluetooth();
        if (!permitted) {
          debugPrint('[RingRecording] Bluetooth permission not granted.');
          await _delay(const Duration(seconds: 30));
          continue;
        }

        try {
          final capture = await _receiveNext(address);
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

  Future<RingRecordingCapture> _receiveNext(String address) async {
    final raw = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('receiveNextRecording', {
      'address': address,
      'scanTimeoutMs': _scanTimeoutMs,
      'waitTimeoutMs': _waitTimeoutMs,
      'commandTimeoutMs': _commandTimeoutMs,
    });
    if (raw == null) {
      throw StateError('Ring bridge returned no recording.');
    }
    final capture = RingRecordingCapture.fromMap(raw);
    final local = capture.localAudioPath;
    if (local.isEmpty || !File(local).existsSync()) {
      throw StateError('Ring recording file is missing.');
    }
    debugPrint(
      '[RingRecording] downloaded fileIndex=${capture.fileIndex} '
      'path=$local bytes=${File(local).lengthSync()} '
      'packets=${capture.packetCount}',
    );
    return capture;
  }

  Future<void> _uploadAndOpenResult(RingRecordingCapture capture) async {
    final router = _router;
    if (router == null) return;

    final localPath = capture.localAudioPath;
    String? contentId;
    String? cloudState;
    String? uploadError;
    final cloud = CloudMediaClient();
    try {
      final token = await AuthService.instance.requireCloudToken();
      final created = await cloud.uploadAudio(
        token: token,
        file: File(localPath),
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
    final durationSec = capture.durationSec.clamp(1, kMaxRecordingDurationSec);
    RecordingSession.set(
      path: localPath,
      duration: durationSec,
      seed: seed,
      timeline: AudioFeatureTimeline(),
      imported: true,
      ring: true,
      titleHint: '指环录音 #${capture.fileIndex}',
      cloudContentId: contentId,
      cloudState: cloudState,
      cloudUploadError: uploadError,
    );
    router.push(AppRoutes.resultPath(durationSec));
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
