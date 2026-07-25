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

/// Press path B: send write job to bound Memory Terminal (mock-capable).
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
        _statusMessage = p.message;
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
      context.push(AppRoutes.myDevices);
      return;
    }
    setState(() {
      _busy = true;
      _statusMessage = null;
      _cardUid = null;
      _jobStatus = null;
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
        _statusMessage = '连接失败';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmWrite() async {
    final job = _job;
    if (job == null || _cardUid == null) return;
    setState(() => _busy = true);
    try {
      await soundPolaDeviceService.confirmWrite(job.jobId);
    } catch (e) {
      setState(() {
        _jobStatus = WriteJobStatus.writeFailed;
        _statusMessage = '确认写入失败';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        final waitingConfirm = _jobStatus == WriteJobStatus.waitingForCard &&
            _cardUid != null &&
            _cardUid!.isNotEmpty;
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
            title: const Text('硬件设备写入'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: widget.onBack,
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
              children: [
                // Zone 1 — sound
                const _SectionLabel('声音'),
                const SizedBox(height: 8),
                _SoundSummary(item: item),
                const SizedBox(height: AppSpacing.section),

                // Zone 2 — device
                const _SectionLabel('设备状态'),
                const SizedBox(height: 8),
                _DeviceStatusCard(
                  device: device,
                  conn: _conn,
                  onBind: () => context.push(AppRoutes.myDevices),
                  onSwitch: () => context.push(AppRoutes.myDevices),
                ),
                const SizedBox(height: AppSpacing.section),

                // Zone 3 — progress
                const _SectionLabel('写入进度'),
                const SizedBox(height: 8),
                _ProgressCard(
                  jobStatus: _jobStatus,
                  cardUid: _cardUid,
                  message: _statusMessage,
                  collected: _collected,
                ),
                const SizedBox(height: AppSpacing.section),

                if (waitingConfirm) ...[
                  _ConfirmPanel(
                    item: item,
                    deviceName: device?.deviceName ?? '—',
                    cardUid: _cardUid!,
                    busy: _busy,
                    onConfirm: _confirmWrite,
                  ),
                  const SizedBox(height: AppSpacing.item),
                  // Mock controls — explicit events only (no auto-success timer).
                  if (!_collected) ...[
                    SecondaryButton(
                      text: '模拟：注入写入失败',
                      onPressed: _busy
                          ? null
                          : () => _mock.mockFailWrite(),
                    ),
                    const SizedBox(height: AppSpacing.item),
                  ],
                ] else if (_jobStatus == WriteJobStatus.waitingForCard &&
                    (_cardUid == null || _cardUid!.isEmpty)) ...[
                  SecondaryButton(
                    text: '模拟：检测到空白声卡',
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
                ],

                if (canStart)
                  PrimaryButton(
                    text: device == null ? '绑定设备' : '发送到设备',
                    onPressed: device == null
                        ? () => context.push(AppRoutes.myDevices)
                        : _startTransfer,
                  ),

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
    required this.onBind,
    required this.onSwitch,
  });

  final SoundPolaDevice? device;
  final DeviceConnectionState conn;
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
              '未绑定设备',
              style: TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '绑定 Memory Terminal 后，可将写入任务发送到硬件完成 NFC 封存。',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            SecondaryButton(text: '绑定设备', onPressed: onBind),
          ],
        ),
      );
    }

    final phaseLabel = switch (conn.phase) {
      DeviceConnectionPhase.unbound => '未绑定',
      DeviceConnectionPhase.boundOffline => '已绑定 · 未连接',
      DeviceConnectionPhase.connecting => '正在连接',
      DeviceConnectionPhase.connected => '已连接',
      DeviceConnectionPhase.transferring => '正在传输',
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
            '$phaseLabel'
            '${device!.batteryLevel != null || conn.batteryLevel != null ? ' · 电量 ${conn.batteryLevel ?? device!.batteryLevel}%' : ''}',
            style: const TextStyle(color: AppColors.accent, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onSwitch,
              child: const Text('切换设备'),
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
  });

  final WriteJobStatus? jobStatus;
  final String? cardUid;
  final String? message;
  final bool collected;

  @override
  Widget build(BuildContext context) {
    final label = collected
        ? '写入完成'
        : (jobStatus?.label ?? '尚未开始');
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
            label,
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
          if (cardUid != null && cardUid!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '声卡 UID · ${_shortUid(cardUid!)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Courier',
                fontSize: 12,
              ),
            ),
          ],
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
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

class _ConfirmPanel extends StatelessWidget {
  const _ConfirmPanel({
    required this.item,
    required this.deviceName,
    required this.cardUid,
    required this.busy,
    required this.onConfirm,
  });

  final SoundMemory item;
  final String deviceName;
  final String cardUid;
  final bool busy;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '确认永久写入',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Text('声音：${item.title}',
              style: const TextStyle(color: AppColors.textSecondary)),
          Text('录制：${item.recordedAt.toLocal()}',
              style: const TextStyle(color: AppColors.textSecondary)),
          Text('目标设备：$deviceName',
              style: const TextStyle(color: AppColors.textSecondary)),
          Text(
            '声卡 UID · ${_ProgressCard._shortUid(cardUid)}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          const Text(
            '写入后不可更换声音。一枚 NFC 声卡永久绑定一段声音。',
            style: TextStyle(color: AppColors.warning, height: 1.4, fontSize: 13),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            text: busy ? '写入中…' : '确认写入',
            onPressed: busy ? null : onConfirm,
          ),
        ],
      ),
    );
  }
}
