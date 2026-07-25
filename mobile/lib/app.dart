import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud/cloud_media_config.dart';
import 'data/sound_repository.dart';
import 'lab/beat_ai_api_config.dart';
import 'router/app_router.dart';
import 'services/auth_service.dart';
import 'services/deep_link_service.dart';
import 'services/ring_recording_service.dart';
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

  static const _micConsentedKey = 'sp_mic_consented';

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_syncRingRecording);
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
    await CloudMediaConfig.init();
    await BeatAiApiConfig.init();
    await AuthService.instance.init();
    await SoundRepository.instance.init();
    await DeepLinkService.instance.init(_router);
    await _resolveMicConsent();
    if (mounted) {
      setState(() => _booting = false);
      _syncRingRecording();
    }
  }

  Future<void> _resolveMicConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberedConsent = prefs.getBool(_micConsentedKey) ?? false;
      final osGranted = await Permission.microphone.isGranted;
      if (osGranted || rememberedConsent) {
        _consented.value = true;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_syncRingRecording);
    RingRecordingService.instance.stop();
    DeepLinkService.instance.dispose();
    _consented.dispose();
    _router.dispose();
    super.dispose();
  }

  void _syncRingRecording() {
    if (_booting || !AuthService.instance.isLoggedIn) {
      RingRecordingService.instance.stop();
      return;
    }
    RingRecordingService.instance.start(_router);
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
    // Router is now attached; flush any cold-start NFC / App Link.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.instance.markRouterReady();
    });
    return MaterialApp.router(
      title: 'SoundPola',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}
