import 'package:flutter/material.dart';
import '../../services/permission_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/sound_visual.dart';

class RecordHomeScreen extends StatelessWidget {
  const RecordHomeScreen({super.key, required this.onStartRecord});

  final VoidCallback onStartRecord;

  Future<void> _start(BuildContext context) async {
    final granted = await PermissionService.ensureMicrophone();
    if (!context.mounted) return;
    if (granted) {
      onStartRecord();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要麦克风权限才能录音')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pageHorizontal,
                ),
                child: const SoundVisualCanvas(seed: 8801, active: false),
              ),
            ),
            // Soft bridge between visual and record control
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
              onTap: () => _start(context),
            ),
            const SizedBox(height: 12),
            const Text(
              '点击开始捕捉声音',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '麦克风就绪 · 地点可在结果页补充',
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.9),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
