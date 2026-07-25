import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../services/auth_service.dart';
import '../services/device_pair_service.dart';
import 'device_models.dart';
import 'device_registry.dart';

/// Unified hardware transport. UI must not call BLE / HTTP directly.
abstract class SoundPolaDeviceService {
  Stream<DeviceConnectionState> get connectionState;
  Stream<HardwareWriteProgress> get writeProgress;

  Future<List<SoundPolaDevice>> scanDevices();
  Future<void> bindDevice(String deviceId);
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<DeviceInfo> getDeviceInfo();
  Future<void> sendWriteJob(HardwareWriteJob job);
  Future<void> confirmWrite(String jobId);
  Future<void> cancelWrite(String jobId);
  Future<HardwareWriteResult> queryWriteResult(String jobId);

  /// Bind via existing Wi-Fi QR pair flow, then persist in [DeviceRegistry].
  Future<SoundPolaDevice> bindViaQr({
    required DevicePairTarget target,
    required String token,
    String? userId,
    String? email,
    String? serverUrl,
  });

  HardwareWriteJob createWriteJob({
    required String deviceId,
    required String soundId,
    String? tokenId,
  });
}

/// Builds compact NFC index JSON + checksum (no audio / frames).
class NfcPayloadBuilder {
  NfcPayloadBuilder._();

  static NfcIndexPayload build({
    required String soundId,
    String? tokenId,
    String? ownerId,
  }) {
    final owner = ownerId ?? AuthService.instance.cloudUserId ?? 'anon';
    final ownerHash = sha256.convert(utf8.encode(owner)).toString().substring(0, 16);
    final issuedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final material = '$soundId|$ownerHash|$issuedAt';
    final signature =
        sha256.convert(utf8.encode(material)).toString().substring(0, 24);
    return NfcIndexPayload(
      soundId: soundId,
      assetUri: 'soundpola://memory/$soundId',
      ownerHash: ownerHash,
      tokenId: tokenId,
      issuedAt: issuedAt,
      signature: signature,
    );
  }

  static String checksum(String payload) =>
      sha256.convert(utf8.encode(payload)).toString();
}

/// Default service: registry + Mock write pipeline (explicit mock events only).
class MockSoundPolaDeviceService implements SoundPolaDeviceService {
  MockSoundPolaDeviceService._();
  static final instance = MockSoundPolaDeviceService._();

  final _connCtrl =
      StreamController<DeviceConnectionState>.broadcast(sync: true);
  final _progCtrl =
      StreamController<HardwareWriteProgress>.broadcast(sync: true);

  DeviceConnectionState _conn = DeviceConnectionState.unbound;
  HardwareWriteJob? _activeJob;
  String? _connectedId;
  final _rng = Random();

  @override
  Stream<DeviceConnectionState> get connectionState => _connCtrl.stream;

  @override
  Stream<HardwareWriteProgress> get writeProgress => _progCtrl.stream;

  DeviceConnectionState get currentConnection => _conn;
  HardwareWriteJob? get activeJob => _activeJob;

  void _emitConn(DeviceConnectionState s) {
    _conn = s;
    _connCtrl.add(s);
  }

  void _emitProg(HardwareWriteProgress p) {
    final job = _activeJob;
    if (job != null && job.jobId == p.jobId) {
      _activeJob = job.copyWith(
        status: p.status,
        cardUid: p.cardUid,
        errorMessage: p.message,
      );
    }
    _progCtrl.add(p);
  }

  @override
  Future<List<SoundPolaDevice>> scanDevices() async {
    await DeviceRegistry.instance.load();
    return DeviceRegistry.instance.devices;
  }

  @override
  Future<void> bindDevice(String deviceId) async {
    await DeviceRegistry.instance.load();
    final existing = DeviceRegistry.instance.getById(deviceId);
    if (existing != null) {
      await DeviceRegistry.instance.setActive(deviceId);
      return;
    }
    // Demo bind without QR (dev only).
    await DeviceRegistry.instance.upsert(
      SoundPolaDevice(
        deviceId: deviceId,
        deviceName: 'SoundPola $deviceId',
        model: 'Memory Terminal',
        firmwareVersion: 'mock-1.0',
        bindingStatus: DeviceBindingStatus.bound,
        lastConnectedAt: DateTime.now(),
        batteryLevel: 88,
        ownerAccountId: AuthService.instance.cloudUserId,
      ),
    );
  }

  @override
  Future<SoundPolaDevice> bindViaQr({
    required DevicePairTarget target,
    required String token,
    String? userId,
    String? email,
    String? serverUrl,
  }) async {
    await DevicePairService.sendToken(
      target: target,
      token: token,
      userId: userId,
      email: email,
      serverUrl: serverUrl,
    );
    final id = target.deviceId?.isNotEmpty == true
        ? target.deviceId!
        : 'SP-${target.ip.replaceAll('.', '')}';
    final device = SoundPolaDevice(
      deviceId: id,
      deviceName: 'Memory Terminal $id',
      model: 'Memory Terminal',
      firmwareVersion: '—',
      bindingStatus: DeviceBindingStatus.bound,
      lastConnectedAt: DateTime.now(),
      batteryLevel: null,
      ownerAccountId: userId ?? AuthService.instance.cloudUserId,
      lastIp: target.ip,
      lastPort: target.port,
    );
    await DeviceRegistry.instance.upsert(device);
    return device;
  }

  @override
  Future<void> connect(String deviceId) async {
    await DeviceRegistry.instance.load();
    final d = DeviceRegistry.instance.getById(deviceId);
    if (d == null) {
      _emitConn(const DeviceConnectionState(
        phase: DeviceConnectionPhase.unbound,
        message: '未绑定设备',
      ));
      throw StateError('device not bound');
    }
    _emitConn(DeviceConnectionState(
      phase: DeviceConnectionPhase.connecting,
      deviceId: deviceId,
    ));
    // No artificial success delay — connection is immediate for mock registry.
    _connectedId = deviceId;
    await DeviceRegistry.instance.upsert(
      d.copyWith(
        lastConnectedAt: DateTime.now(),
        batteryLevel: d.batteryLevel ?? 76,
      ),
    );
    _emitConn(DeviceConnectionState(
      phase: DeviceConnectionPhase.connected,
      deviceId: deviceId,
      batteryLevel: d.batteryLevel ?? 76,
    ));
  }

  @override
  Future<void> disconnect() async {
    _connectedId = null;
    final has = DeviceRegistry.instance.hasBoundDevice;
    _emitConn(
      has
          ? DeviceConnectionState(
              phase: DeviceConnectionPhase.boundOffline,
              deviceId: DeviceRegistry.instance.activeDeviceId,
            )
          : DeviceConnectionState.unbound,
    );
  }

  @override
  Future<DeviceInfo> getDeviceInfo() async {
    await DeviceRegistry.instance.load();
    final d = DeviceRegistry.instance.activeDevice;
    if (d == null) {
      throw StateError('no device');
    }
    return DeviceInfo(device: d);
  }

  @override
  HardwareWriteJob createWriteJob({
    required String deviceId,
    required String soundId,
    String? tokenId,
  }) {
    final payload = NfcPayloadBuilder.build(
      soundId: soundId,
      tokenId: tokenId,
    ).encode();
    final nonce = List.generate(8, (_) => _rng.nextInt(16).toRadixString(16))
        .join();
    return HardwareWriteJob(
      jobId: 'job_${DateTime.now().microsecondsSinceEpoch}',
      deviceId: deviceId,
      soundId: soundId,
      payload: payload,
      payloadChecksum: NfcPayloadBuilder.checksum(payload),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      nonce: nonce,
    );
  }

  @override
  Future<void> sendWriteJob(HardwareWriteJob job) async {
    if (_connectedId != job.deviceId) {
      _activeJob = job.copyWith(status: WriteJobStatus.connectionFailed);
      _emitProg(HardwareWriteProgress(
        jobId: job.jobId,
        status: WriteJobStatus.connectionFailed,
        message: WriteJobStatus.connectionFailed.appHint,
      ));
      _emitConn(DeviceConnectionState(
        phase: DeviceConnectionPhase.writeFailed,
        deviceId: job.deviceId,
        message: WriteJobStatus.connectionFailed.appHint,
      ));
      return;
    }
    _activeJob = job;
    _emitConn(DeviceConnectionState(
      phase: DeviceConnectionPhase.transferring,
      deviceId: job.deviceId,
      batteryLevel: _conn.batteryLevel,
    ));
    _emitProg(HardwareWriteProgress(
      jobId: job.jobId,
      status: WriteJobStatus.transferring,
      message: WriteJobStatus.transferring.appHint,
    ));
    // Instant transfer ack for mock — still event-driven, not a timed fake success.
    _emitProg(HardwareWriteProgress(
      jobId: job.jobId,
      status: WriteJobStatus.transferred,
      message: WriteJobStatus.transferred.appHint,
    ));
    _emitProg(HardwareWriteProgress(
      jobId: job.jobId,
      status: WriteJobStatus.waitingForCard,
      message: WriteJobStatus.waitingForCard.appHint,
    ));
    _emitConn(DeviceConnectionState(
      phase: DeviceConnectionPhase.waitingForCard,
      deviceId: job.deviceId,
      batteryLevel: _conn.batteryLevel,
      message: WriteJobStatus.waitingForCard.appHint,
    ));
  }

  /// Mock-only: device detects a card. Blank cards are confirmed on-device
  /// (APP never confirms write); already-bound cards fail immediately.
  void mockDetectCard({String? cardUid, bool alreadyBound = false}) {
    final job = _activeJob;
    if (job == null || job.status != WriteJobStatus.waitingForCard) return;
    if (alreadyBound) {
      _emitProg(HardwareWriteProgress(
        jobId: job.jobId,
        status: WriteJobStatus.cardAlreadyBound,
        cardUid: cardUid ?? 'UID-BOUND',
        message: WriteJobStatus.cardAlreadyBound.appHint,
      ));
      _emitConn(DeviceConnectionState(
        phase: DeviceConnectionPhase.writeFailed,
        deviceId: job.deviceId,
        message: '声卡已绑定',
      ));
      return;
    }
    final uid = cardUid ??
        'UID-${List.generate(4, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
    _activeJob = job.copyWith(cardUid: uid);
    // Device-side confirm → write → verify (APP only observes).
    unawaited(_runDeviceSideWrite(job.jobId, uid));
  }

  Future<void> _runDeviceSideWrite(String jobId, String cardUid) async {
    final job = _activeJob;
    if (job == null || job.jobId != jobId) return;
    _emitProg(HardwareWriteProgress(
      jobId: jobId,
      status: WriteJobStatus.writing,
      cardUid: cardUid,
      message: WriteJobStatus.writing.appHint,
    ));
    _emitConn(DeviceConnectionState(
      phase: DeviceConnectionPhase.writing,
      deviceId: job.deviceId,
      batteryLevel: _conn.batteryLevel,
    ));
    _emitProg(HardwareWriteProgress(
      jobId: jobId,
      status: WriteJobStatus.verifying,
      cardUid: cardUid,
      message: WriteJobStatus.verifying.appHint,
    ));
    _emitConn(DeviceConnectionState(
      phase: DeviceConnectionPhase.verifying,
      deviceId: job.deviceId,
      batteryLevel: _conn.batteryLevel,
    ));
    _emitProg(HardwareWriteProgress(
      jobId: jobId,
      status: WriteJobStatus.success,
      cardUid: cardUid,
      message: WriteJobStatus.success.appHint,
    ));
    _emitConn(DeviceConnectionState(
      phase: DeviceConnectionPhase.writeSuccess,
      deviceId: job.deviceId,
      batteryLevel: _conn.batteryLevel,
    ));
  }

  /// Kept for transport API compatibility; real devices confirm on-device.
  /// Mock: if a card UID is already set, continues the write pipeline.
  @override
  Future<void> confirmWrite(String jobId) async {
    final job = _activeJob;
    if (job == null || job.jobId != jobId) {
      throw StateError('no active job');
    }
    if (job.cardUid == null || job.cardUid!.isEmpty) {
      throw StateError('card not confirmed');
    }
    if (job.status != WriteJobStatus.waitingForCard) {
      throw StateError('invalid status ${job.status}');
    }
    await _runDeviceSideWrite(jobId, job.cardUid!);
  }

  /// Mock-only failure injection while a job is active on device.
  void mockFailWrite({WriteJobStatus status = WriteJobStatus.writeFailed}) {
    final job = _activeJob;
    if (job == null) return;
    _emitProg(HardwareWriteProgress(
      jobId: job.jobId,
      status: status,
      cardUid: job.cardUid,
      message: status.appHint,
    ));
    _emitConn(DeviceConnectionState(
      phase: DeviceConnectionPhase.writeFailed,
      deviceId: job.deviceId,
      message: status.appHint,
    ));
  }

  @override
  Future<void> cancelWrite(String jobId) async {
    final job = _activeJob;
    if (job == null || job.jobId != jobId) return;
    if (job.status.isTerminal) return;
    _emitProg(HardwareWriteProgress(
      jobId: jobId,
      status: WriteJobStatus.cancelled,
    ));
    await disconnect();
  }

  @override
  Future<HardwareWriteResult> queryWriteResult(String jobId) async {
    final job = _activeJob;
    if (job == null || job.jobId != jobId) {
      return HardwareWriteResult(
        jobId: jobId,
        status: WriteJobStatus.unknown,
        message: '无任务记录',
      );
    }
    return HardwareWriteResult(
      jobId: job.jobId,
      status: job.status,
      cardUid: job.cardUid,
      message: job.errorMessage,
    );
  }
}

/// App-wide accessor (swap implementation later for BLE / LAN).
SoundPolaDeviceService get soundPolaDeviceService =>
    MockSoundPolaDeviceService.instance;
