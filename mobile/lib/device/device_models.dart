import 'dart:convert';

/// Binding lifecycle for a SoundPola hardware device.
enum DeviceBindingStatus {
  unbound,
  bound,
  revoked,
}

/// High-level connection / session state shown in UI.
enum DeviceConnectionPhase {
  unbound,
  boundOffline,
  connecting,
  connected,
  transferring,
  waitingForCard,
  writing,
  verifying,
  writeSuccess,
  writeFailed,
  offline,
}

/// Write job pipeline (driven by transport events — never fixed delays).
enum WriteJobStatus {
  created,
  connecting,
  transferring,
  transferred,
  waitingForCard,
  writing,
  verifying,
  success,
  connectionFailed,
  transferFailed,
  cardNotDetected,
  cardAlreadyBound,
  writeFailed,
  verifyFailed,
  cancelled,
  timeout,
  unknown,
}

extension WriteJobStatusX on WriteJobStatus {
  bool get isTerminal =>
      this == WriteJobStatus.success ||
      this == WriteJobStatus.connectionFailed ||
      this == WriteJobStatus.transferFailed ||
      this == WriteJobStatus.cardNotDetected ||
      this == WriteJobStatus.cardAlreadyBound ||
      this == WriteJobStatus.writeFailed ||
      this == WriteJobStatus.verifyFailed ||
      this == WriteJobStatus.cancelled ||
      this == WriteJobStatus.timeout ||
      this == WriteJobStatus.unknown;

  bool get isSuccess => this == WriteJobStatus.success;

  String get label => switch (this) {
        WriteJobStatus.created => '已创建',
        WriteJobStatus.connecting => '未连接',
        WriteJobStatus.transferring => '正在发送',
        WriteJobStatus.transferred => '设备已接收',
        WriteJobStatus.waitingForCard => '等待放入声卡',
        WriteJobStatus.writing => '正在写入',
        WriteJobStatus.verifying => '正在校验',
        WriteJobStatus.success => '写入成功',
        WriteJobStatus.connectionFailed => '未连接',
        WriteJobStatus.transferFailed => '写入失败',
        WriteJobStatus.cardNotDetected => '写入失败',
        WriteJobStatus.cardAlreadyBound => '写入失败',
        WriteJobStatus.writeFailed => '写入失败',
        WriteJobStatus.verifyFailed => '写入失败',
        WriteJobStatus.cancelled => '写入失败',
        WriteJobStatus.timeout => '写入失败',
        WriteJobStatus.unknown => '写入失败',
      };

  /// APP 侧状态提示（写入在设备端完成，此处仅同步进度）。
  String get appHint => switch (this) {
        WriteJobStatus.created => '请确认已连接设备后发送写入任务',
        WriteJobStatus.connecting => '请先连接 SoundPola 设备',
        WriteJobStatus.transferring => '正在向设备发送写入请求',
        WriteJobStatus.transferred => '请求已发送，请前往设备继续操作',
        WriteJobStatus.waitingForCard => '请在设备中放入一枚空白 Sound Piece',
        WriteJobStatus.writing => '设备正在写入，请勿移走声卡',
        WriteJobStatus.verifying => '正在验证声卡绑定结果',
        WriteJobStatus.success => '声音已写入并加入收藏',
        WriteJobStatus.connectionFailed => '请先连接 SoundPola 设备',
        WriteJobStatus.transferFailed ||
        WriteJobStatus.cardNotDetected ||
        WriteJobStatus.cardAlreadyBound ||
        WriteJobStatus.writeFailed ||
        WriteJobStatus.verifyFailed ||
        WriteJobStatus.cancelled ||
        WriteJobStatus.timeout ||
        WriteJobStatus.unknown =>
          '写入未完成，可重新发送或重试',
      };
}

class SoundPolaDevice {
  const SoundPolaDevice({
    required this.deviceId,
    required this.deviceName,
    required this.model,
    required this.firmwareVersion,
    required this.bindingStatus,
    this.lastConnectedAt,
    this.batteryLevel,
    this.supportedCapabilities = const ['nfc_write', 'holo'],
    this.ownerAccountId,
    this.lastIp,
    this.lastPort,
  });

  final String deviceId;
  final String deviceName;
  final String model;
  final String firmwareVersion;
  final DeviceBindingStatus bindingStatus;
  final DateTime? lastConnectedAt;
  final int? batteryLevel;
  final List<String> supportedCapabilities;
  final String? ownerAccountId;
  final String? lastIp;
  final int? lastPort;

  SoundPolaDevice copyWith({
    String? deviceName,
    String? model,
    String? firmwareVersion,
    DeviceBindingStatus? bindingStatus,
    DateTime? lastConnectedAt,
    int? batteryLevel,
    List<String>? supportedCapabilities,
    String? ownerAccountId,
    String? lastIp,
    int? lastPort,
    bool clearLastConnected = false,
  }) {
    return SoundPolaDevice(
      deviceId: deviceId,
      deviceName: deviceName ?? this.deviceName,
      model: model ?? this.model,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      bindingStatus: bindingStatus ?? this.bindingStatus,
      lastConnectedAt:
          clearLastConnected ? null : (lastConnectedAt ?? this.lastConnectedAt),
      batteryLevel: batteryLevel ?? this.batteryLevel,
      supportedCapabilities:
          supportedCapabilities ?? this.supportedCapabilities,
      ownerAccountId: ownerAccountId ?? this.ownerAccountId,
      lastIp: lastIp ?? this.lastIp,
      lastPort: lastPort ?? this.lastPort,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'model': model,
        'firmwareVersion': firmwareVersion,
        'bindingStatus': bindingStatus.name,
        'lastConnectedAtMs': lastConnectedAt?.millisecondsSinceEpoch,
        'batteryLevel': batteryLevel,
        'supportedCapabilities': supportedCapabilities,
        'ownerAccountId': ownerAccountId,
        'lastIp': lastIp,
        'lastPort': lastPort,
      };

  factory SoundPolaDevice.fromJson(Map<String, dynamic> json) {
    return SoundPolaDevice(
      deviceId: json['deviceId'] as String,
      deviceName: (json['deviceName'] as String?) ?? 'SoundPola Device',
      model: (json['model'] as String?) ?? 'Memory Terminal',
      firmwareVersion: (json['firmwareVersion'] as String?) ?? '—',
      bindingStatus: DeviceBindingStatus.values.firstWhere(
        (e) => e.name == json['bindingStatus'],
        orElse: () => DeviceBindingStatus.bound,
      ),
      lastConnectedAt: (json['lastConnectedAtMs'] as num?) != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['lastConnectedAtMs'] as num).toInt(),
            )
          : null,
      batteryLevel: (json['batteryLevel'] as num?)?.toInt(),
      supportedCapabilities: (json['supportedCapabilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['nfc_write', 'holo'],
      ownerAccountId: json['ownerAccountId'] as String?,
      lastIp: json['lastIp'] as String?,
      lastPort: (json['lastPort'] as num?)?.toInt(),
    );
  }
}

/// Minimal NFC index — never full audio / frames / cover.
class NfcIndexPayload {
  const NfcIndexPayload({
    required this.soundId,
    required this.assetUri,
    required this.ownerHash,
    required this.issuedAt,
    required this.signature,
    this.tokenId,
    this.protocol = 'soundpola',
    this.version = 1,
  });

  final String protocol;
  final int version;
  final String soundId;
  final String assetUri;
  final String ownerHash;
  final String? tokenId;
  final int issuedAt;
  final String signature;

  Map<String, dynamic> toJson() => {
        'protocol': protocol,
        'version': version,
        'soundId': soundId,
        'assetUri': assetUri,
        'ownerHash': ownerHash,
        if (tokenId != null) 'tokenId': tokenId,
        'issuedAt': issuedAt,
        'signature': signature,
      };

  String encode() => jsonEncode(toJson());
}

class HardwareWriteJob {
  HardwareWriteJob({
    required this.jobId,
    required this.deviceId,
    required this.soundId,
    required this.payload,
    required this.payloadChecksum,
    required this.createdAt,
    required this.nonce,
    this.protocolVersion = 1,
    this.status = WriteJobStatus.created,
    this.cardUid,
    this.errorMessage,
  });

  final String jobId;
  final String deviceId;
  final String soundId;
  final String payload;
  final String payloadChecksum;
  final int protocolVersion;
  final int createdAt;
  final String nonce;
  WriteJobStatus status;
  String? cardUid;
  String? errorMessage;

  HardwareWriteJob copyWith({
    WriteJobStatus? status,
    String? cardUid,
    String? errorMessage,
  }) {
    return HardwareWriteJob(
      jobId: jobId,
      deviceId: deviceId,
      soundId: soundId,
      payload: payload,
      payloadChecksum: payloadChecksum,
      protocolVersion: protocolVersion,
      createdAt: createdAt,
      nonce: nonce,
      status: status ?? this.status,
      cardUid: cardUid ?? this.cardUid,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class DeviceConnectionState {
  const DeviceConnectionState({
    required this.phase,
    this.deviceId,
    this.batteryLevel,
    this.message,
  });

  final DeviceConnectionPhase phase;
  final String? deviceId;
  final int? batteryLevel;
  final String? message;

  static const unbound = DeviceConnectionState(
    phase: DeviceConnectionPhase.unbound,
  );
}

class HardwareWriteProgress {
  const HardwareWriteProgress({
    required this.jobId,
    required this.status,
    this.cardUid,
    this.message,
  });

  final String jobId;
  final WriteJobStatus status;
  final String? cardUid;
  final String? message;
}

class HardwareWriteResult {
  const HardwareWriteResult({
    required this.jobId,
    required this.status,
    this.cardUid,
    this.message,
  });

  final String jobId;
  final WriteJobStatus status;
  final String? cardUid;
  final String? message;

  bool get verifiedSuccess => status == WriteJobStatus.success;
}

class DeviceInfo {
  const DeviceInfo({
    required this.device,
    this.writeModuleReady = true,
    this.storageLabel = '就绪',
  });

  final SoundPolaDevice device;
  final bool writeModuleReady;
  final String storageLabel;
}
