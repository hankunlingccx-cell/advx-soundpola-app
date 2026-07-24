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
  late final GoRouter _router = createRouter();
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
            child: Text(
              'SoundPola',
              style: TextStyle(
                color: Color(0xFFF4F7F6),
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
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
