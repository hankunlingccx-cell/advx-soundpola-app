import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/press_resume.dart';
import '../data/session.dart';
import '../screens/account/account_screen.dart';
import '../screens/auth/auth_screens.dart';
import '../screens/collection/category_play_screen.dart';
import '../screens/collection/collection_screen.dart';
import '../screens/drafts/drafts_screen.dart';
import '../screens/press/press_screens.dart';
import '../screens/record/record_home_screen.dart';
import '../screens/record/recording_screen.dart';
import '../screens/record/result_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/design_components.dart';
import 'app_routes.dart';

export 'app_routes.dart';

void openPressFlow(BuildContext context, String id, {bool chainOnly = false}) {
  if (!AuthService.instance.isLoggedIn) {
    PressResume.set(id: id, chainOnlyMode: chainOnly);
    context.push(AppRoutes.loginPath(draftId: id));
    return;
  }
  context.push(AppRoutes.pressMethodPath(id, chainOnly: chainOnly));
}

GoRouter createRouter() {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: AuthService.instance,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final onSplash = loc == AppRoutes.splash;
      final onAuth = loc == AppRoutes.login ||
          loc == AppRoutes.register ||
          loc == AppRoutes.accountReady;

      // 启动页自行分流，不在此打断
      if (onSplash) return null;

      // 进入主流程前必须登录
      if (!AuthService.instance.isLoggedIn) {
        return onAuth ? null : AppRoutes.login;
      }

      // 已登录时离开登录页（Press 恢复场景除外）
      if (loc == AppRoutes.login) {
        if (PressResume.hasPending) return null;
        return AppRoutes.main;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => LoginScreen(
          draftId: state.uri.queryParameters['draftId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.accountReady,
        builder: (context, state) => const AccountReadyScreen(),
      ),
      GoRoute(
        path: AppRoutes.account,
        builder: (context, state) => const AccountScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => child,
        routes: [
          GoRoute(
            path: AppRoutes.main,
            builder: (context, state) {
              final tab =
                  int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
              return MainShell(initialTab: tab);
            },
          ),
          GoRoute(
            path: AppRoutes.recording,
            builder: (context, state) => RecordingScreen(
              onCancel: () => context.pop(),
              onComplete: (path, duration) {
                RecordingSession.set(path: path, duration: duration);
                context.pushReplacement(AppRoutes.resultPath(duration));
              },
            ),
          ),
          GoRoute(
            path: AppRoutes.result,
            builder: (context, state) {
              final duration = RecordingSession.durationSec != 0
                  ? RecordingSession.durationSec
                  : int.tryParse(
                          state.uri.queryParameters['duration'] ?? '1') ??
                      1;
              final audioPath = RecordingSession.audioPath ?? '';
              return ResultScreen(
                durationSec: duration,
                audioPath: audioPath,
                onSaved: () => context.go(AppRoutes.mainTab(1)),
                onReRecord: () {
                  RecordingSession.clear();
                  context.pushReplacement(AppRoutes.recording);
                },
              );
            },
          ),
          GoRoute(
            path: AppRoutes.draftDetail,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return DraftDetailScreen(
                id: id,
                onBack: () => context.pop(),
                onDeleted: () => context.pop(),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.pressMethod,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              final chainOnly =
                  state.uri.queryParameters['chainOnly'] == '1';
              return PressMethodScreen(
                id: id,
                chainOnly: chainOnly,
                onBack: () => context.pop(),
                onNfc: () {
                  if (chainOnly) {
                    context.pushReplacement(
                      AppRoutes.pressProgressPath(id, chainOnly: true),
                    );
                  } else {
                    context.push(AppRoutes.pressDetectPath(id));
                  }
                },
              );
            },
          ),
          GoRoute(
            path: AppRoutes.pressDetect,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return PressDetectScreen(
                id: id,
                onBack: () => context.pop(),
                onDetected: () =>
                    context.pushReplacement(AppRoutes.pressRevealPath(id)),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.pressReveal,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return PressRevealScreen(
                id: id,
                onBack: () => context.pop(),
                onConfirm: () =>
                    context.pushReplacement(AppRoutes.pressConfirmPath(id)),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.pressConfirm,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return PressConfirmScreen(
                id: id,
                onBack: () => context.pop(),
                onConfirm: () =>
                    context.pushReplacement(AppRoutes.pressProgressPath(id)),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.pressProgress,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              final chainOnly =
                  state.uri.queryParameters['chainOnly'] == '1';
              return PressProgressScreen(
                id: id,
                chainOnly: chainOnly,
                onDone: () =>
                    context.pushReplacement(AppRoutes.pressDonePath(id)),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.pressDone,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return PressDoneScreen(
                id: id,
                onCollection: () => context.go(AppRoutes.mainTab(2)),
                onOpenCategoryPlay: (category) {
                  context.go(
                    AppRoutes.categoryPlayPath(category, soundId: id),
                  );
                },
              );
            },
          ),
          GoRoute(
            path: AppRoutes.categoryPlay,
            builder: (context, state) {
              // go_router 已对 path 参数做百分号解码；不可再 Uri.decodeComponent，
              // 否则中文等非 ASCII 会抛 Illegal percent encoding in URI。
              final category = state.pathParameters['categoryId'] ?? '';
              final soundId = state.uri.queryParameters['soundId'];
              return CategoryPlayScreen(
                category: category,
                initialSoundId: soundId,
                onBack: () => context.pop(),
              );
            },
          ),
        ],
      ),
    ],
  );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _tab = widget.initialTab;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: IndexedStack(
        index: _tab,
        children: [
          RecordHomeScreen(onStartRecord: () => context.push(AppRoutes.recording)),
          DraftsScreen(
            onOpenDetail: (id) => context.push(AppRoutes.draftPath(id)),
            onStartRecord: () {
              setState(() => _tab = 0);
              context.push(AppRoutes.recording);
            },
            onOpenCollection: () => setState(() => _tab = 2),
            onLogin: () => context.push(AppRoutes.login),
          ),
          CollectionScreen(
            onOpenCategoryPlay: (category, {String? soundId}) {
              context.push(
                AppRoutes.categoryPlayPath(category, soundId: soundId),
              );
            },
            onStartRecord: () {
              setState(() => _tab = 0);
              context.push(AppRoutes.recording);
            },
            onOpenDrafts: () => setState(() => _tab = 1),
            onLogin: () => context.push(AppRoutes.login),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        selected: _tab,
        onSelect: (index) => setState(() => _tab = index),
      ),
    );
  }
}
