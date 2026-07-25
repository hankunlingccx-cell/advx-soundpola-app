import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/press_resume.dart';
import '../data/session.dart';
import '../screens/account/account_screen.dart';
import '../screens/account/my_devices_screen.dart';
import '../screens/account/pair_device_screen.dart';
import '../screens/auth/auth_screens.dart';
import '../screens/collection/category_play_screen.dart';
import '../screens/collection/collection_screen.dart';
import '../screens/content/content_resolve_screen.dart';
import '../screens/drafts/drafts_screen.dart';
import '../screens/press/hardware_press_screen.dart';
import '../screens/press/press_screens.dart';
import '../screens/record/permission_screen.dart';
import '../screens/record/record_home_screen.dart';
import '../screens/record/recording_screen.dart';
import '../screens/record/result_screen.dart';
import '../screens/lab/sound_lab_screen.dart';
import '../screens/settings/server_settings_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../services/auth_service.dart';
import '../services/deep_link_service.dart';
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

/// 进入 NFC 写卡流程。
void openPressFlow(BuildContext context, String id, {bool chainOnly = false}) {
  if (!AuthService.instance.isLoggedIn) {
    PressResume.set(id: id, chainOnlyMode: chainOnly);
    context.push(AppRoutes.loginPath(draftId: id));
    return;
  }
  context.push(AppRoutes.pressMethodPath(id, chainOnly: chainOnly));
}

GoRouter createRouter({required ValueNotifier<bool> consented}) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    // NFC custom scheme (soundpola://c/{id}) arrives as platform default route;
    // do not let go_router treat the full URI as a path location.
    overridePlatformDefaultLocation: true,
    refreshListenable: Listenable.merge([consented, AuthService.instance]),
    onException: (context, state, router) {
      final contentId = DeepLinkService.contentIdFromUri(state.uri);
      if (contentId != null) {
        router.go(AppRoutes.contentPath(contentId));
        return;
      }
      router.go(AppRoutes.splash);
    },
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final onSplash = loc == AppRoutes.splash;
      final onPermission = loc == AppRoutes.permission;
      final onAuth = loc == AppRoutes.login ||
          loc == AppRoutes.register ||
          loc == AppRoutes.accountReady ||
          loc == AppRoutes.privateKeyBackup;
      final onSettings = loc == AppRoutes.serverSettings;
      // Custom scheme keeps host as "c"; path-only /c/{id} uses pathSegments.
      final onResolve = DeepLinkService.contentIdFromUri(state.uri) != null ||
          state.uri.path.startsWith('/c/');

      // 启动页自行分流
      if (onSplash) return null;

      // 麦克风权限页优先（未同意时）
      if (!consented.value) {
        return (onPermission || onResolve) ? null : AppRoutes.permission;
      }
      if (onPermission) {
        return AuthService.instance.isLoggedIn
            ? AppRoutes.main
            : AppRoutes.login;
      }

      // 进入主流程前必须登录
      if (!AuthService.instance.isLoggedIn) {
        return (onAuth || onSettings || onResolve) ? null : AppRoutes.login;
      }

      // 已登录时离开登录页
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
        path: AppRoutes.myDevices,
        builder: (context, state) => const MyDevicesScreen(),
      ),
      GoRoute(
        path: AppRoutes.deviceDetail,
        builder: (context, state) {
          final raw = state.pathParameters['deviceId'] ?? '';
          return DeviceDetailScreen(deviceId: raw);
        },
      ),
      GoRoute(
        path: AppRoutes.serverSettings,
        builder: (context, state) => const ServerSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.soundLab,
        builder: (context, state) => const SoundLabScreen(),
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
                fromImport: RecordingSession.fromImport,
                suggestedTitle: RecordingSession.suggestedTitle,
                onSaved: () => context.go(AppRoutes.mainTab(1)),
                onReRecord: () {
                  final wasImport = RecordingSession.fromImport;
                  RecordingSession.clear();
                  if (wasImport) {
                    context.pop();
                  } else {
                    context.pushReplacement(AppRoutes.recording);
                  }
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
            path: AppRoutes.pressHardware,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return HardwarePressScreen(
                id: id,
                onBack: () => context.pop(),
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
      extendBody: false,
      body: IndexedStack(
        index: _tab,
        children: [
          RecordHomeScreen(
            onStartRecord: () => context.push(AppRoutes.recording),
            onImported: (result) {
              RecordingSession.set(
                path: result.path,
                duration: result.durationSec,
                seed: result.visualSeed,
                timeline: result.timeline,
                imported: true,
                titleHint: result.suggestedTitle,
              );
              context.push(AppRoutes.resultPath(result.durationSec));
            },
          ),
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
