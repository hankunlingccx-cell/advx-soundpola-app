import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/audio_import_service.dart';
import '../../services/audio_recording_service.dart';
import '../../services/permission_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/empty_state_panel.dart';
import '../../widgets/sound_visual.dart';

class RecordHomeScreen extends StatefulWidget {
  const RecordHomeScreen({
    super.key,
    required this.onStartRecord,
    required this.onImported,
  });

  final VoidCallback onStartRecord;
  final void Function(AudioImportResult result) onImported;

  @override
  State<RecordHomeScreen> createState() => _RecordHomeScreenState();
}

class _RecordHomeScreenState extends State<RecordHomeScreen> {
  bool? _micGranted;
  bool _permanentlyDenied = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _refreshMic();
    // Prefetch audio isolate so first record tap isn't blocked on spawn.
    AudioRecordingService.instance.warmUp();
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

  Future<void> _importLocal() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await AudioImportService.instance.pickAndImport();
      if (!mounted) return;
      if (result == null) return;
      widget.onImported(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : '导入失败：$e',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Widget _importEntry({required bool compact}) {
    return TextButton(
      onPressed: _importing ? null : _importLocal,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 4 : 8,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: _importing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: AppColors.accent,
              ),
            )
          : Text(
              '导入本地音频',
              style: TextStyle(
                fontSize: compact ? 12.5 : 13.5,
                fontWeight: FontWeight.w500,
                color: AppColors.accent.withValues(alpha: 0.85),
                letterSpacing: 0.2,
              ),
            ),
    );
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageHorizontal,
                6,
                AppSpacing.pageHorizontal,
                2,
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'SoundPola',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const ConnectDeviceIconButton(),
                  const SizedBox(width: 8),
                  const AccountAvatarButton(),
                ],
              ),
            ),
            Expanded(
              child: blocked
                  ? EmptyStatePanel(
                      statusCode: 'MIC ACCESS REQUIRED',
                      title: '需要麦克风权限',
                      description: '没有 SoundPola 无法捕捉声音。\n权限仅用于录制，不会后台监听。'
                          '${_importing ? '' : '\n也可先导入本地音频。'}',
                      visual: const EmptyMicPortVisual(locked: true),
                      variant: EmptyStateVariant.blocked,
                      primaryLabel: _permanentlyDenied
                          ? '前往系统设置'
                          : '允许麦克风权限',
                      onPrimary: _requestMic,
                      secondaryLabel: _importing ? '导入中…' : '导入本地音频',
                      onSecondary: _importing ? null : _importLocal,
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final h = constraints.maxHeight;
                        final w = constraints.maxWidth;
                        const bottomBlock = 188.0;
                        final visualBudget =
                            (h - bottomBlock - 8).clamp(120.0, h);
                        // 主体宽 74%–82%；视觉中心约在可用区 39%–43%。
                        final visualW =
                            (w * 0.78).clamp(0.0, visualBudget * 0.92);
                        final visualCenterY = (h * 0.40).clamp(
                          visualW * 0.48,
                          h - bottomBlock - visualW * 0.35,
                        );
                        final visualTop =
                            (visualCenterY - visualW / 2).clamp(0.0, h * 0.18);

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.pageHorizontal,
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                top: visualTop,
                                left: (w - visualW) / 2 -
                                    AppSpacing.pageHorizontal,
                                width: visualW,
                                height: visualW,
                                child: const SoundVisualCanvas(
                                  seed: 8801,
                                  active: false,
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 10,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      height: 16,
                                      width: 10,
                                      child: CustomPaint(
                                        painter: _StandbyLinkPainter(),
                                      ),
                                    ),
                                    RecordFab(
                                      state: RecordFabState.idle,
                                      onTap: _start,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'LISTENING STANDBY',
                                      style: TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 9.5,
                                        letterSpacing: 0.9,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    const Text(
                                      '等待捕捉声音',
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '按下按钮，麦克风口将开始接收环境声。',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.textSecondary
                                            .withValues(alpha: 0.85),
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    _importEntry(compact: true),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hairline energy thread + rising motes between visualization and Record FAB.
class _StandbyLinkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final paint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.12)
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), paint);
    for (var i = 0; i < 2; i++) {
      final y = size.height * (0.28 + i * 0.38);
      canvas.drawCircle(
        Offset(cx, y),
        0.9,
        Paint()..color = AppColors.accent.withValues(alpha: 0.18 - i * 0.05),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
