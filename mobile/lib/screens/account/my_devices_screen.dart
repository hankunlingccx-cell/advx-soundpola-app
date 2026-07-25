import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../device/device_models.dart';
import '../../device/device_registry.dart';
import '../../device/device_service.dart';
import '../../router/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/empty_state_panel.dart';

class MyDevicesScreen extends StatefulWidget {
  const MyDevicesScreen({super.key});

  @override
  State<MyDevicesScreen> createState() => _MyDevicesScreenState();
}

class _MyDevicesScreenState extends State<MyDevicesScreen> {
  @override
  void initState() {
    super.initState();
    DeviceRegistry.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DeviceRegistry.instance,
      builder: (context, _) {
        final devices = DeviceRegistry.instance.devices;
        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          appBar: AppBar(
            backgroundColor: AppColors.bgPrimary,
            elevation: 0,
            foregroundColor: AppColors.textPrimary,
            title: const Text('我的设备'),
          ),
          body: SafeArea(
            child: devices.isEmpty
                ? EmptyStatePanel(
                    statusCode: 'NO DEVICE BOUND',
                    title: '尚未绑定设备',
                    description:
                        '确认手机与设备在同一 WiFi，扫描 Memory Terminal 屏幕上的配对二维码完成连接。',
                    visual: const EmptyTrayVisual(),
                    variant: EmptyStateVariant.firstUse,
                    primaryLabel: 'WiFi 扫码连接设备',
                    onPrimary: () => context.push(AppRoutes.pairDevice),
                  )
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
                    children: [
                      for (final d in devices) ...[
                        _DeviceTile(
                          device: d,
                          active: d.deviceId ==
                              DeviceRegistry.instance.activeDeviceId,
                          onTap: () => context.push(
                            AppRoutes.deviceDetailPath(d.deviceId),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.item),
                      ],
                      const SizedBox(height: AppSpacing.section),
                      SecondaryButton(
                        text: 'WiFi 扫码连接新设备',
                        onPressed: () => context.push(AppRoutes.pairDevice),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.active,
    required this.onTap,
  });

  final SoundPolaDevice device;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.15),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                ),
                child: const Icon(Icons.memory, color: AppColors.accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.deviceName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${device.model} · ${active ? '当前' : '已绑定'}'
                      '${device.batteryLevel != null ? ' · ${device.batteryLevel}%' : ''}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    DeviceRegistry.instance.load();
  }

  Future<void> _reconnect() async {
    setState(() => _connecting = true);
    try {
      await soundPolaDeviceService.connect(widget.deviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已连接')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('连接失败')),
        );
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _rename() async {
    final d = DeviceRegistry.instance.getById(widget.deviceId);
    if (d == null) return;
    final ctrl = TextEditingController(text: d.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        title: const Text('修改设备名称', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: '设备名称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await DeviceRegistry.instance.rename(widget.deviceId, name);
    }
  }

  Future<void> _unbind() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        title: const Text('解除绑定？', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          '将清除本机与该设备的连接凭证。不会删除你的声音记忆或 Collection。',
          style: TextStyle(color: AppColors.textSecondary, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解除绑定', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DeviceRegistry.instance.unbind(widget.deviceId);
    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DeviceRegistry.instance,
      builder: (context, _) {
        final d = DeviceRegistry.instance.getById(widget.deviceId);
        if (d == null) {
          return Scaffold(
            backgroundColor: AppColors.bgPrimary,
            appBar: AppBar(
              backgroundColor: AppColors.bgPrimary,
              title: const Text('设备详情'),
            ),
            body: const Center(
              child: Text('设备不存在', style: TextStyle(color: AppColors.textSecondary)),
            ),
          );
        }
        final last = d.lastConnectedAt;
        final lastLabel = last == null
            ? '—'
            : '${last.year}-${last.month.toString().padLeft(2, '0')}-${last.day.toString().padLeft(2, '0')} '
                '${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}';

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          appBar: AppBar(
            backgroundColor: AppColors.bgPrimary,
            elevation: 0,
            foregroundColor: AppColors.textPrimary,
            title: Text(d.deviceName),
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
            children: [
              _InfoRow(label: '设备 ID', value: d.deviceId),
              _InfoRow(label: '产品型号', value: d.model),
              _InfoRow(
                label: '连接状态',
                value: DeviceRegistry.instance.activeDeviceId == d.deviceId
                    ? '当前设备'
                    : '已绑定',
              ),
              _InfoRow(
                label: '电量',
                value: d.batteryLevel != null ? '${d.batteryLevel}%' : '—',
              ),
              _InfoRow(label: '固件版本', value: d.firmwareVersion),
              _InfoRow(label: '最近连接', value: lastLabel),
              _InfoRow(label: '写入模块', value: '就绪'),
              _InfoRow(label: '设备存储', value: '就绪'),
              const SizedBox(height: AppSpacing.section),
              PrimaryButton(
                text: _connecting ? '正在连接…' : '重新连接',
                onPressed: _connecting ? null : _reconnect,
              ),
              const SizedBox(height: AppSpacing.item),
              SecondaryButton(text: '修改设备名称', onPressed: _rename),
              const SizedBox(height: AppSpacing.item),
              SecondaryButton(
                text: '检查固件更新',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('固件检查即将推出')),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.item),
              SecondaryButton(
                text: '设为当前设备',
                onPressed: () => DeviceRegistry.instance.setActive(d.deviceId),
              ),
              const SizedBox(height: AppSpacing.section),
              SecondaryButton(
                text: '解除绑定',
                danger: true,
                onPressed: _unbind,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
