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
      color: AppColors.canvasBg,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.section),
            const Text(
              'Record',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.ink400,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 320,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.collectionCard),
                  child: Container(
                    color: AppColors.primary50,
                    padding: const EdgeInsets.all(AppSpacing.section),
                    child: const SoundVisualCanvas(seed: 8801, active: false),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.block),
            RecordFab(recording: false, onTap: () => _start(context)),
            const SizedBox(height: 12),
            const Text('点击开始录音', style: TextStyle(color: AppColors.ink600, fontSize: 14)),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
