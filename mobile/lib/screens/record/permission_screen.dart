import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/permission_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/sound_visual.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _continue() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final granted = await PermissionService.ensureMicrophone();
    if (!mounted) return;
    if (granted) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('sp_mic_consented', true);
      } catch (_) {}
      widget.onContinue();
    } else {
      setState(() {
        _loading = false;
        _error = '需要麦克风权限才能录制声音。请在系统设置中开启。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.block),
              const Text(
                '捕捉此刻的声音',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'SoundPola 需要麦克风权限来录制声音，并可选择记录地点以丰富记忆。',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.item),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 14),
                ),
              ],
              const Spacer(),
              const AspectRatio(
                aspectRatio: 1,
                child: SoundVisualCanvas(
                  seed: 2048,
                  mode: SoundVisualMode.idle,
                  amplitude: 0.08,
                ),
              ),
              const Spacer(),
              PrimaryButton(
                text: _loading ? '请求权限中…' : '允许麦克风并继续',
                onPressed: _loading ? null : _continue,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.tight),
                SecondaryButton(
                  text: '打开系统设置',
                  onPressed: PermissionService.openSettings,
                ),
              ],
              const SizedBox(height: AppSpacing.section),
            ],
          ),
        ),
      ),
    );
  }
}
