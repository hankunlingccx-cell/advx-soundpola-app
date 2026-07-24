import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class SoundpolaApp extends StatefulWidget {
  const SoundpolaApp({super.key});

  @override
  State<SoundpolaApp> createState() => _SoundpolaAppState();
}

class _SoundpolaAppState extends State<SoundpolaApp> {
  final _consented = ValueNotifier<bool>(false);
  late final GoRouter _router = createRouter(consented: _consented);

  @override
  void dispose() {
    _consented.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SoundPola',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: _router,
    );
  }
}
