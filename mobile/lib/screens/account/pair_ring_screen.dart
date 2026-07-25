import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/permission_service.dart';
import '../../services/ring_recording_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';

/// 蓝牙配对页：扫描并以列表展示名称以 ring 开头的指环（名称 + MAC）。
class PairRingScreen extends StatefulWidget {
  const PairRingScreen({super.key});

  @override
  State<PairRingScreen> createState() => _PairRingScreenState();
}

class _PairRingScreenState extends State<PairRingScreen> {
  bool _scanning = false;
  bool _pairing = false;
  String? _error;
  List<RingScanDevice> _devices = const [];
  String? _pairingAddress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    if (_scanning || _pairing) return;
    setState(() {
      _scanning = true;
      _error = null;
      _devices = const [];
    });
    try {
      final permitted = await PermissionService.ensureRingBluetooth();
      if (!permitted) {
        if (!mounted) return;
        setState(() {
          _error = '需要蓝牙权限才能扫描指环';
          _scanning = false;
        });
        return;
      }
      final found = await RingRecordingService.instance.scanRings();
      if (!mounted) return;
      setState(() {
        _devices = found;
        _scanning = false;
        if (found.isEmpty) {
          _error = '未发现指环。请确认设备已开机，且名称以 ring 开头。';
        }
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = '当前平台暂不支持指环蓝牙';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = e.message == null ? '扫描失败' : '扫描失败：${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = '扫描失败：$e';
      });
    }
  }

  Future<void> _pair(RingScanDevice device) async {
    if (_pairing || _scanning) return;
    setState(() {
      _pairing = true;
      _pairingAddress = device.address;
      _error = null;
    });
    try {
      final bound = await RingRecordingService.instance.pairRing(
        address: device.address,
        displayName: device.name,
      );
      if (!mounted) return;
      final battery = bound.batteryLevel == null ? '' : ' · ${bound.batteryLevel}%';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface1,
          title: const Text('指环已连接', style: TextStyle(color: AppColors.textPrimary)),
          content: Text(
            '${device.name}\n${device.address}$battery\n\n之后在指环上完成录音，松开后会自动下载并进入录音结果页。',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('完成', style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      );
      if (mounted) context.pop();
    } on MissingPluginException {
      _fail('当前平台暂不支持指环蓝牙连接');
    } on PlatformException catch (e) {
      _fail(e.message == null ? '指环连接失败' : '指环连接失败：${e.message}');
    } catch (e) {
      _fail('指环连接失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _pairing = false;
          _pairingAddress = null;
        });
      }
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('蓝牙配对指环'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.item),
              const Text(
                '仅显示名称以 ring 开头的设备。选择你的指环完成蓝牙配对；配对后由指环按键录音，结束后自动下载。',
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.item),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error, height: 1.4),
                ),
                const SizedBox(height: AppSpacing.item),
              ],
              Expanded(child: _buildList()),
              const SizedBox(height: AppSpacing.item),
              SecondaryButton(
                text: _scanning ? '正在扫描…' : '重新扫描',
                onPressed: (_scanning || _pairing) ? null : _scan,
              ),
              const SizedBox(height: AppSpacing.item),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_scanning && _devices.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 12),
            Text(
              '正在搜索 ring…',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_devices.isEmpty) {
      return const Center(
        child: Text(
          '附近没有可配对的指环',
          style: TextStyle(color: AppColors.textTertiary),
        ),
      );
    }

    return ListView.separated(
      itemCount: _devices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final device = _devices[index];
        final busy = _pairing && _pairingAddress == device.address;
        return Material(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.card),
            onTap: (_pairing || _scanning) ? null : () => _pair(device),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.bluetooth, color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          device.address,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (device.rssi != null)
                          Text(
                            '信号 ${device.rssi} dBm',
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Text(
                      '配对',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
