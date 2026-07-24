import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'router/app_router.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

class SoundpolaApp extends StatefulWidget {
  const SoundpolaApp({super.key});

  @override
  State<SoundpolaApp> createState() => _SoundpolaAppState();
}

class _SoundpolaAppState extends State<SoundpolaApp> {
  final _consented = ValueNotifier<bool>(false);
  late final GoRouter _router = createRouter(consented: _consented);
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF090C0B),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    await AuthService.instance.init();
    if (mounted) setState(() => _booting = false);
  }

  @override
  void dispose() {
    _consented.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: const Scaffold(
          backgroundColor: Color(0xFF000000),
          body: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF63E0CB)),
            ),
          ),
        ),
      );
    }
    return MaterialApp.router(
      title: 'SoundPola',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}
