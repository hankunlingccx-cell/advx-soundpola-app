import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/press_resume.dart';
import '../data/session.dart';
import '../data/sound_repository.dart';
import '../screens/account/account_screen.dart';
import '../screens/account/pair_device_screen.dart';
import '../screens/auth/auth_screens.dart';
import '../screens/collection/collection_screen.dart';
import '../screens/content/content_resolve_screen.dart';
import '../screens/drafts/drafts_screen.dart';
import '../screens/press/press_screens.dart';
import '../screens/record/permission_screen.dart';
import '../screens/record/record_home_screen.dart';
import '../screens/record/recording_screen.dart';
import '../screens/record/result_screen.dart';
import '../screens/settings/server_settings_screen.dart';
import '../services/auth_service.dart';
import '../services/mint_pipeline.dart';
import '../theme/app_colors.dart';
import '../widgets/design_components.dart';
import 'app_routes.dart';

export 'app_routes.dart';

/// 手动触发云端上传管道。未登录先登录再恢复。
void startMint(BuildContext context, String id) {
  if (!AuthService.instance.isLoggedIn) {
    PressResume.set(id: id, entryPoint: 'mint');
    context.push(AppRoutes.loginPath(draftId: id));
    return;
  }
  MintPipeline.instance.startCloud(id);
}

/// 手动触发链上铸造（需要 cloudReady 状态）。
void startChain(BuildContext context, String id) {
  if (!AuthService.instance.isLoggedIn) {
    PressResume.set(id: id, entryPoint: 'mint');
    context.push(AppRoutes.loginPath(draftId: id));
    return;
  }
  MintPipeline.instance.startChain(id);
}

/// 进入 NFC 写卡流程，云端 READY 即可写入（上链为可选）。
void openPressFlow(BuildContext context, String id) {
  final item = SoundRepository.instance.get(id);
  if (item == null) return;
  final canWrite = item.status == SoundStatus.cloudReady ||
      item.status == SoundStatus.chainPending ||
      item.status == SoundStatus.chainReady ||
      item.status == SoundStatus.chainFailed ||
      (item.status == SoundStatus.collected &&
          item.contentId != null &&
          item.discId != null);
  if (!canWrite) return;
  if (!AuthService.instance.isLoggedIn) {
    PressResume.set(id: id);
    context.push(AppRoutes.loginPath(draftId: id));
    return;
  }
  context.push(AppRoutes.pressMethodPath(id));
}

GoRouter createRouter({required ValueNotifier<bool> consented}) {
  return GoRouter(
    initialLocation: AppRoutes.permission,
    refreshListenable: Listenable.merge([consented, AuthService.instance]),
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final onPermission = loc == AppRoutes.permission;
      final onAuth = loc == AppRoutes.login ||
          loc == AppRoutes.register ||
          loc == AppRoutes.accountReady ||
          loc == AppRoutes.privateKeyBackup;
      final onSettings = loc == AppRoutes.serverSettings;
      final onResolve = state.uri.path.startsWith('/c/');

      // 1) 麦克风权限页优先
      if (!consented.value) {
        return (onPermission || onResolve) ? null : AppRoutes.permission;
      }
      if (onPermission) {
        return AuthService.instance.isLoggedIn
            ? AppRoutes.main
            : AppRoutes.login;
      }

      // 2) 进入主流程前必须登录
      if (!AuthService.instance.isLoggedIn) {
        return (onAuth || onSettings || onResolve) ? null : AppRoutes.login;
      }

      // 3) 已登录时离开登录页
      if (loc == AppRoutes.login) {
        if (PressResume.hasPending) return null;
        return AppRoutes.main;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.permission,
        builder: (context, state) => PermissionScreen(
          onContinue: () => consented.value = true,
        ),
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
        path: AppRoutes.privateKeyBackup,
        builder: (context, state) => const PrivateKeyBackupScreen(),
      ),
      GoRoute(
        path: AppRoutes.account,
        builder: (context, state) => const AccountScreen(),
      ),
      GoRoute(
        path: AppRoutes.pairDevice,
        builder: (context, state) => const PairDeviceScreen(),
      ),
      GoRoute(
        path: AppRoutes.serverSettings,
        builder: (context, state) => const ServerSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.resolveContent,
        builder: (context, state) => ContentResolveScreen(
          contentId: state.pathParameters['contentId']!,
        ),
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
                onMint: () => startMint(context, id),
                onChain: () => startChain(context, id),
                onPress: () => openPressFlow(context, id),
                onDeleted: () => context.pop(),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.pressMethod,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return PressMethodScreen(
                id: id,
                onBack: () => context.pop(),
                onNfc: () => context.push(AppRoutes.pressDetectPath(id)),
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
              return PressProgressScreen(
                id: id,
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
                onMemory: () => context.push(AppRoutes.memoryPath(id)),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.memory,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return MemoryScreen(
                id: id,
                onBack: () => context.pop(),
                onWriteNfc: (mid) => openPressFlow(context, mid),
                onChain: (mid) => startChain(context, mid),
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
            onMint: (id) => startMint(context, id),
            onChain: (id) => startChain(context, id),
            onPress: (id) => openPressFlow(context, id),
            onStartRecord: () {
              setState(() => _tab = 0);
              context.push(AppRoutes.recording);
            },
            onLogin: () => context.push(AppRoutes.login),
          ),
          CollectionScreen(
            onOpenMemory: (id) => context.push(AppRoutes.memoryPath(id)),
            onLogin: () => context.push(AppRoutes.login),
            onWriteNfc: (id) => openPressFlow(context, id),
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
