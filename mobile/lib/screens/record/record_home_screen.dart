import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/permission_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/empty_state_panel.dart';
import '../../widgets/sound_visual.dart';

class RecordHomeScreen extends StatefulWidget {
  const RecordHomeScreen({super.key, required this.onStartRecord});

  final VoidCallback onStartRecord;

  @override
  State<RecordHomeScreen> createState() => _RecordHomeScreenState();
}

class _RecordHomeScreenState extends State<RecordHomeScreen> {
  bool? _micGranted;
  bool _permanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _refreshMic();
  }

  Future<void> _refreshMic() async {
    final status = await Permission.microphone.status;
    if (!mounted) return;
    setState(() {
      _micGranted = status.isGranted;
      _permanentlyDenied = status.isPermanentlyDenied;
    });
  }

  Future<void> _requestMic() async {
    if (_permanentlyDenied) {
      await PermissionService.openSettings();
      await _refreshMic();
      return;
    }
    final granted = await PermissionService.ensureMicrophone();
    if (!mounted) return;
    await _refreshMic();
    if (granted) widget.onStartRecord();
  }

  Future<void> _start() async {
    if (_micGranted == true) {
      widget.onStartRecord();
      return;
    }
    await _requestMic();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _micGranted == false;

    return ColoredBox(
      color: AppColors.bgPrimary,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageHorizontal,
                vertical: AppSpacing.item,
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'SoundPola',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const AccountAvatarButton(),
                ],
              ),
            ),
            Expanded(
              child: blocked
                  ? EmptyStatePanel(
                      statusCode: 'MIC ACCESS REQUIRED',
                      title: '需要麦克风权限',
                      description: '没有 SoundPola 无法捕捉声音。\n权限仅用于录制，不会后台监听。',
                      visual: const EmptyMicPortVisual(locked: true),
                      variant: EmptyStateVariant.blocked,
                      primaryLabel: _permanentlyDenied
                          ? '前往系统设置'
                          : '允许麦克风权限',
                      onPrimary: _requestMic,
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.pageHorizontal,
                      ),
                      child: Column(
                        children: [
                          const Expanded(
                            child: SoundVisualCanvas(seed: 8801, active: false),
                          ),
                          Container(
                            height: 20,
                            width: 2,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(1),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppColors.accent.withValues(alpha: 0.18),
                                  AppColors.accent.withValues(alpha: 0.05),
                                ],
                              ),
                            ),
                          ),
                          RecordFab(
                            state: RecordFabState.idle,
                            onTap: _start,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'LISTENING STANDBY',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                              letterSpacing: 1.4,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '等待捕捉声音',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '按下按钮，麦克风口将开始接收环境声。',
                            style: TextStyle(
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.9,
                              ),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
