import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/disc_rarity.dart';
import '../../data/sound_repository.dart';
import '../../device/device_models.dart';
import '../../device/device_registry.dart';
import '../../device/device_service.dart';
import '../../router/app_routes.dart';
import '../../services/chain_service.dart';
import '../../services/nfc_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/empty_state_panel.dart';
import '../../widgets/sound_visual.dart';

/// 发送写入任务至 Memory Terminal；插入声卡／确认／校验均在设备端完成。
class HardwarePressScreen extends StatefulWidget {
  const HardwarePressScreen({
    super.key,
    required this.id,
    required this.onBack,
  });

  final String id;
  final VoidCallback onBack;

  @override
  State<HardwarePressScreen> createState() => _HardwarePressScreenState();
}

class _HardwarePressScreenState extends State<HardwarePressScreen> {
  StreamSubscription<DeviceConnectionState>? _connSub;
  StreamSubscription<HardwareWriteProgress>? _progSub;

  DeviceConnectionState _conn = DeviceConnectionState.unbound;
  WriteJobStatus? _jobStatus;
  String? _cardUid;
  String? _statusMessage;
  HardwareWriteJob? _job;
  bool _busy = false;
  bool _collected = false;

  MockSoundPolaDeviceService get _mock => MockSoundPolaDeviceService.instance;

  @override
  void initState() {
    super.initState();
    DeviceRegistry.instance.load();
    _conn = _mock.currentConnection;
    _connSub = soundPolaDeviceService.connectionState.listen((s) {
      if (mounted) setState(() => _conn = s);
    });
    _progSub = soundPolaDeviceService.writeProgress.listen((p) {
      if (!mounted) return;
      setState(() {
        _jobStatus = p.status;
        _cardUid = p.cardUid ?? _cardUid;
        _statusMessage = p.message ?? p.status.appHint;
      });
      if (p.status == WriteJobStatus.success) {
        _onVerifiedSuccess(p);
      }
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _progSub?.cancel();
    super.dispose();
  }

  Future<void> _onVerifiedSuccess(HardwareWriteProgress p) async {
    if (_collected) return;
    final item = SoundRepository.instance.get(widget.id);
    if (item == null) return;
    final result = await soundPolaDeviceService.queryWriteResult(p.jobId);
    if (!result.verifiedSuccess) return;
    _collected = true;
    final discId = NfcService.instance.generateDiscId('HW');
    final rarity =
        DiscRarity.values[item.visualSeed % DiscRarity.values.length];
    final assetId = await ChainService.instance.submitAsset(
      soundId: item.id,
      discId: discId,
      rarityCode: rarity.code,
      series: 'Hardware',
    );
    SoundRepository.instance.markCollected(
      item.id,
      discId,
      assetId,
      nfcTagId: result.cardUid,
      boundDeviceId: _job?.deviceId,
      discRarity: rarity,
      discSeries: 'Hardware',
    );
    if (mounted) setState(() {});
  }

  Future<void> _startTransfer() async {
    final device = DeviceRegistry.instance.activeDevice;
    if (device == null) {
      context.push(AppRoutes.pairDevice);
      return;
    }
    setState(() {
      _busy = true;
      _statusMessage = WriteJobStatus.transferring.appHint;
      _cardUid = null;
      _jobStatus = WriteJobStatus.transferring;
      _collected = false;
    });
    try {
      await soundPolaDeviceService.connect(device.deviceId);
      final job = soundPolaDeviceService.createWriteJob(
        deviceId: device.deviceId,
        soundId: widget.id,
      );
      _job = job;
      await soundPolaDeviceService.sendWriteJob(job);
    } catch (e) {
      setState(() {
        _jobStatus = WriteJobStatus.connectionFailed;
        _statusMessage = WriteJobStatus.connectionFailed.appHint;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _notConnected {
    final device = DeviceRegistry.instance.activeDevice;
    if (device == null) return true;
    return _conn.phase == DeviceConnectionPhase.unbound ||
        _conn.phase == DeviceConnectionPhase.boundOffline ||
        _conn.phase == DeviceConnectionPhase.offline ||
        _jobStatus == WriteJobStatus.connectionFailed;
  }

  @override
  Widget build(BuildContext context) {
    final item = SoundRepository.instance.get(widget.id);
    if (item == null) {
      return Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: SafeArea(
          child: EmptyStatePanel(
            statusCode: 'NO SOUND TO PRESS',
            title: '没有可写入的声音',
            description: '先录制一段声音，再发送到硬件设备。',
            visual: const EmptyTrayVisual(),
            primaryLabel: '返回',
            onPrimary: widget.onBack,
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: DeviceRegistry.instance,
      builder: (context, _) {
        final device = DeviceRegistry.instance.activeDevice;
        final waitingOnDevice = _jobStatus == WriteJobStatus.transferred ||
            _jobStatus == WriteJobStatus.waitingForCard ||
            _jobStatus == WriteJobStatus.writing ||
            _jobStatus == WriteJobStatus.verifying;
        final canStart = !_busy &&
            !_collected &&
            (_jobStatus == null ||
                (_jobStatus!.isTerminal &&
                    _jobStatus != WriteJobStatus.success));

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          appBar: AppBar(
            backgroundColor: AppColors.bgPrimary,
            elevation: 0,
            foregroundColor: AppColors.textPrimary,
            title: const Text('发送至设备写入'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: widget.onBack,
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
              children: [
                const _SectionLabel('声音'),
                const SizedBox(height: 8),
                _SoundSummary(item: item),
                const SizedBox(height: AppSpacing.section),

                const _SectionLabel('设备'),
                const SizedBox(height: 8),
                _DeviceStatusCard(
                  device: device,
                  conn: _conn,
                  notConnected: device == null ||
                      (_jobStatus == null && _notConnected),
                  onBind: () => context.push(AppRoutes.pairDevice),
                  onSwitch: () => context.push(AppRoutes.myDevices),
                ),
                const SizedBox(height: AppSpacing.section),

                const _SectionLabel('写入任务状态'),
                const SizedBox(height: 8),
                _ProgressCard(
                  jobStatus: _jobStatus,
                  cardUid: _cardUid,
                  message: _statusMessage,
                  collected: _collected,
                  noDevice: device == null,
                ),
                const SizedBox(height: AppSpacing.item),
                const Text(
                  'APP 仅发送写入任务。放入 Sound Piece、确认写入与硬件校验均在设备端完成，状态会同步回本页。',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: AppSpacing.section),

                if (waitingOnDevice && !_collected) ...[
                  SecondaryButton(
                    text: '模拟：设备放入空白声卡并写入',
                    onPressed: _busy ? null : () => _mock.mockDetectCard(),
                  ),
                  const SizedBox(height: AppSpacing.item),
                  SecondaryButton(
                    text: '模拟：声卡已绑定',
                    onPressed: _busy
                        ? null
                        : () => _mock.mockDetectCard(alreadyBound: true),
                  ),
                  const SizedBox(height: AppSpacing.item),
                  SecondaryButton(
                    text: '模拟：写入失败',
                    onPressed:
                        _busy ? null : () => _mock.mockFailWrite(),
                  ),
                  const SizedBox(height: AppSpacing.section),
                ],

                if (canStart)
                  PrimaryButton(
                    text: device == null ? '连接 SoundPola 设备' : '发送至设备',
                    onPressed: device == null
                        ? () => context.push(AppRoutes.pairDevice)
                        : _startTransfer,
                  ),

                if (_jobStatus != null &&
                    _jobStatus!.isTerminal &&
                    _jobStatus != WriteJobStatus.success &&
                    !_collected) ...[
                  const SizedBox(height: AppSpacing.item),
                  SecondaryButton(
                    text: '重新发送写入任务',
                    onPressed: device == null ? null : _startTransfer,
                  ),
                ],

                if (_collected) ...[
                  PrimaryButton(
                    text: '查看收藏',
                    onPressed: () => context.go(AppRoutes.mainTab(2)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textTertiary,
        fontSize: 12,
        letterSpacing: 0.06,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SoundSummary extends StatelessWidget {
  const _SoundSummary({required this.item});
  final SoundMemory item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.chip),
            child: SizedBox(
              width: 64,
              height: 64,
              child: SoundVisualCanvas(
                seed: item.visualSeed,
                mode: SoundVisualMode.complete,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.recordedAt.toLocal()} · ${item.durationSec}s',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceStatusCard extends StatelessWidget {
  const _DeviceStatusCard({
    required this.device,
    required this.conn,
    required this.notConnected,
    required this.onBind,
    required this.onSwitch,
  });

  final SoundPolaDevice? device;
  final DeviceConnectionState conn;
  final bool notConnected;
  final VoidCallback onBind;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    if (device == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '未连接',
              style: TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '请先连接 SoundPola 设备',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            SecondaryButton(text: 'WiFi 扫码连接', onPressed: onBind),
          ],
        ),
      );
    }

    final phaseLabel = switch (conn.phase) {
      DeviceConnectionPhase.unbound => '未绑定',
      DeviceConnectionPhase.boundOffline => '已绑定 · 未连接',
      DeviceConnectionPhase.connecting => '正在连接',
      DeviceConnectionPhase.connected => '已连接',
      DeviceConnectionPhase.transferring => '正在发送',
      DeviceConnectionPhase.waitingForCard => '等待放入声卡',
      DeviceConnectionPhase.writing => '正在写入',
      DeviceConnectionPhase.verifying => '正在校验',
      DeviceConnectionPhase.writeSuccess => '写入成功',
      DeviceConnectionPhase.writeFailed => '写入失败',
      DeviceConnectionPhase.offline => '设备离线',
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            device!.deviceName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            notConnected &&
                    conn.phase != DeviceConnectionPhase.connected &&
                    conn.phase != DeviceConnectionPhase.transferring &&
                    conn.phase != DeviceConnectionPhase.waitingForCard &&
                    conn.phase != DeviceConnectionPhase.writing &&
                    conn.phase != DeviceConnectionPhase.verifying &&
                    conn.phase != DeviceConnectionPhase.writeSuccess
                ? '未连接 · 请先连接 SoundPola 设备'
                : '$phaseLabel'
                    '${device!.batteryLevel != null || conn.batteryLevel != null ? ' · 电量 ${conn.batteryLevel ?? device!.batteryLevel}%' : ''}',
            style: TextStyle(
              color: notConnected ? AppColors.warning : AppColors.accent,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onSwitch,
              child: const Text('选择 / 切换设备'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.jobStatus,
    required this.cardUid,
    required this.message,
    required this.collected,
    required this.noDevice,
  });

  final WriteJobStatus? jobStatus;
  final String? cardUid;
  final String? message;
  final bool collected;
  final bool noDevice;

  @override
  Widget build(BuildContext context) {
    final statusLabel = collected
        ? '写入成功'
        : noDevice && jobStatus == null
            ? '未连接'
            : (jobStatus?.label ?? '待发送');
    final hint = collected
        ? WriteJobStatus.success.appHint
        : noDevice && jobStatus == null
            ? '请先连接 SoundPola 设备'
            : (message ?? jobStatus?.appHint ?? '选择录音后，将写入任务发送至已连接设备');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusLabel,
            style: TextStyle(
              color: collected || jobStatus == WriteJobStatus.success
                  ? AppColors.accent
                  : (jobStatus?.isTerminal == true &&
                          jobStatus != WriteJobStatus.success
                      ? AppColors.error
                      : AppColors.textPrimary),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          if (cardUid != null && cardUid!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '声卡 UID · ${_shortUid(cardUid!)}',
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontFamily: 'Courier',
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _shortUid(String uid) {
    if (uid.length <= 12) return uid;
    return '${uid.substring(0, 6)}…${uid.substring(uid.length - 4)}';
  }
}
