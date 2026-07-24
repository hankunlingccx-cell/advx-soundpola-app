import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/session.dart';
import '../data/sound_repository.dart';
import '../screens/collection/collection_screen.dart';
import '../screens/drafts/drafts_screen.dart';
import '../screens/press/press_screens.dart';
import '../screens/record/permission_screen.dart';
import '../screens/record/record_home_screen.dart';
import '../screens/record/recording_screen.dart';
import '../screens/record/result_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/design_components.dart';

class AppRoutes {
  static const permission = '/permission';
  static const main = '/';
  static const recording = '/recording';
  static const result = '/result';
  static const draftDetail = '/draft/:id';
  static const pressMethod = '/press/method/:id';
  static const pressDetect = '/press/detect/:id';
  static const pressConfirm = '/press/confirm/:id';
  static const pressProgress = '/press/progress/:id';
  static const pressDone = '/press/done/:id';
  static const memory = '/memory/:id';

  static String mainTab(int tab) => '/?tab=$tab';
  static String resultPath(int duration) => '/result?duration=$duration';
  static String draftPath(String id) => '/draft/$id';
  static String pressProgressPath(String id, {bool chainOnly = false}) =>
      chainOnly ? '/press/progress/$id?chainOnly=1' : '/press/progress/$id';
  static String pressMethodPath(String id, {bool chainOnly = false}) =>
      chainOnly ? '/press/method/$id?chainOnly=1' : '/press/method/$id';
  static String pressDetectPath(String id) => '/press/detect/$id';
  static String pressConfirmPath(String id) => '/press/confirm/$id';
  static String pressDonePath(String id) => '/press/done/$id';
  static String memoryPath(String id) => '/memory/$id';
}

GoRouter createRouter({required ValueNotifier<bool> consented}) {
  return GoRouter(
    initialLocation: consented.value ? AppRoutes.main : AppRoutes.permission,
    refreshListenable: consented,
    redirect: (context, state) {
      final onPermission = state.matchedLocation == AppRoutes.permission;
      if (!consented.value && !onPermission) return AppRoutes.permission;
      if (consented.value && onPermission) return AppRoutes.main;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.permission,
        builder: (context, state) => PermissionScreen(
          onContinue: () => consented.value = true,
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => child,
        routes: [
          GoRoute(
            path: AppRoutes.main,
            builder: (context, state) {
              final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
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
                  : int.tryParse(state.uri.queryParameters['duration'] ?? '1') ?? 1;
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
                onPress: () {
                  final item = SoundRepository.instance.get(id);
                  if (item?.status == SoundStatus.chainFailed) {
                    context.push(AppRoutes.pressMethodPath(id, chainOnly: true));
                  } else {
                    context.push(AppRoutes.pressMethodPath(id));
                  }
                },
                onDeleted: () => context.pop(),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.pressMethod,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              final chainOnly = state.uri.queryParameters['chainOnly'] == '1';
              return PressMethodScreen(
                id: id,
                chainOnly: chainOnly,
                onBack: () => context.pop(),
                onNfc: () {
                  if (chainOnly) {
                    context.pushReplacement(AppRoutes.pressProgressPath(id, chainOnly: true));
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
                onDetected: () => context.pushReplacement(AppRoutes.pressConfirmPath(id)),
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
                onConfirm: () => context.pushReplacement(AppRoutes.pressProgressPath(id)),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.pressProgress,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              final chainOnly = state.uri.queryParameters['chainOnly'] == '1';
              return PressProgressScreen(
                id: id,
                chainOnly: chainOnly,
                onDone: () => context.pushReplacement(AppRoutes.pressDonePath(id)),
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
      backgroundColor: AppColors.canvasBg,
      body: IndexedStack(
        index: _tab,
        children: [
          RecordHomeScreen(onStartRecord: () => context.push(AppRoutes.recording)),
          DraftsScreen(
            onOpenDetail: (id) => context.push(AppRoutes.draftPath(id)),
            onPress: (id) {
              final item = SoundRepository.instance.get(id);
              if (item?.status == SoundStatus.chainFailed) {
                context.push(AppRoutes.pressMethodPath(id, chainOnly: true));
              } else {
                context.push(AppRoutes.pressMethodPath(id));
              }
            },
            onStartRecord: () {
              setState(() => _tab = 0);
              context.push(AppRoutes.recording);
            },
          ),
          CollectionScreen(onOpenMemory: (id) => context.push(AppRoutes.memoryPath(id))),
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        selected: _tab,
        onSelect: (index) => setState(() => _tab = index),
      ),
    );
  }
}
