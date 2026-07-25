import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../router/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/sound_visual.dart';

/// 启动页：品牌动效 + 登录态分流（已登录 → 主页，否则 → 登录）。
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // 最短展示，避免闪屏；Auth 已在 App 启动时 init。
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    final loggedIn = AuthService.instance.isLoggedIn;
    context.go(loggedIn ? AppRoutes.main : AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Spacer(flex: 2),
            Text(
              'SoundPola',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 34,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '把声音收成可以回看的记忆',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            SizedBox(height: AppSpacing.section),
            SizedBox(
              width: 220,
              height: 220,
              child: SoundVisualCanvas(seed: 2048, active: true),
            ),
            Spacer(flex: 3),
            Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.section),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
