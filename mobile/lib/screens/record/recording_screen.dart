import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../data/session.dart';
import '../../services/audio_recording_service.dart';
import '../../services/permission_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../visual/audio_feature_timeline.dart';
import '../../widgets/audio_drive_debug.dart';
import '../../widgets/design_components.dart';
import '../../widgets/empty_state_panel.dart';
import '../../widgets/sound_visual.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({
    super.key,
    required this.onCancel,
    required this.onComplete,
  });

  final VoidCallback onCancel;
  final void Function(String path, int durationSec) onComplete;

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final _recorder = AudioRecordingService.instance;
  Timer? _uiTimer;
  Timer? _hintTimer;
  int _seconds = 0;
  bool _paused = false;
  bool _busy = false;
  /// start() 完成前禁止暂停／完成，避免 stop 时路径仍为 null。
  bool _ready = false;
  bool _starting = true;
  String? _error;
  String? _levelHint;
  String? _tooShortPath;
  int _tooShortDuration = 0;
  int _visualSeed = DateTime.now().millisecondsSinceEpoch % 900000 + 1000;
  AudioFeatureTimeline? _shortTimeline;
  static const _minDurationSec = 3;
  /// Debug HUD for AGC calibration (kDebugMode only).
  bool _showAudioDebug = kDebugMode;

  @override
  void initState() {
    super.initState();
    _beginRecording();
  }

  Future<void> _beginRecording() async {
    setState(() {
      _starting = true;
      _ready = false;
      _error = null;
      _seconds = 0;
      _paused = false;
      _levelHint = null;
    });
    final granted = await PermissionService.ensureMicrophone();
    if (!granted) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = '麦克风权限未开启';
        });
      }
      return;
    }
    try {
      _visualSeed = DateTime.now().millisecondsSinceEpoch % 900000 + 1000;
      await _recorder.start(visualSeed: _visualSeed).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw TimeoutException('麦克风启动超时，请重试'),
      );
      if (!mounted) return;
      setState(() {
        _starting = false;
        _ready = true;
      });
      _uiTimer?.cancel();
      _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_paused && mounted) {
          setState(() => _seconds = _recorder.elapsedSeconds());
        }
      });
      // Level hint at ~2 Hz — does not drive visual; visual reads isolate features.
      _hintTimer?.cancel();
      _hintTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        final n = _recorder.featuresNotifier;
        if (!mounted || n == null || _paused) return;
        final rms = n.value.rms;
        final hint = rms < 0.15
            ? '音量偏低，靠近声源'
            : (rms > 0.85 ? '音量偏高' : '音量正常');
        if (hint != _levelHint) {
          setState(() => _levelHint = hint);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _ready = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _hintTimer?.cancel();
    if (_recorder.isRecording) {
      _recorder.cancel();
    }
    super.dispose();
  }

  Future<void> _confirmCancel() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃本次录音？'),
        content: const Text('当前录制内容不会被保存。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续录音')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃录音', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      await _recorder.cancel();
      widget.onCancel();
    }
  }

  Future<void> _togglePause() async {
    if (!_ready || _busy) return;
    if (_paused) {
      await _recorder.resume();
    } else {
      await _recorder.pause();
    }
    setState(() => _paused = !_paused);
  }

  void _completeWith(
    String path,
    int durationSec, {
    int? seed,
    AudioFeatureTimeline? timeline,
  }) {
    RecordingSession.set(
      path: path,
      duration: durationSec,
      seed: seed ?? _visualSeed,
      timeline: timeline ??
          AudioFeatureTimeline(
            samples: List.from(_recorder.featureTimeline.samples),
          ),
    );
    widget.onComplete(path, durationSec);
  }

  Future<void> _finish() async {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    try {
      final result = await _recorder.stop();
      _uiTimer?.cancel();
      _hintTimer?.cancel();
      if (!mounted) return;
      if (result.durationSec < _minDurationSec) {
        setState(() {
          _busy = false;
          _ready = false;
          _tooShortPath = result.path;
          _tooShortDuration = result.durationSec;
          _visualSeed = result.visualSeed;
          _shortTimeline = result.timeline;
        });
        return;
      }
      _completeWith(
        result.path,
        result.durationSec,
        seed: result.visualSeed,
        timeline: result.timeline,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _ready = false;
          _error = '保存录音失败：$e';
        });
      }
    }
  }

  Future<void> _keepShortRecording() async {
    final path = _tooShortPath;
    if (path == null) return;
    _completeWith(
      path,
      _tooShortDuration,
      seed: _visualSeed,
      timeline: _shortTimeline,
    );
  }

  Future<void> _rerunAfterShort() async {
    setState(() {
      _tooShortPath = null;
      _tooShortDuration = 0;
    });
    await _beginRecording();
  }

  @override
  Widget build(BuildContext context) {
    if (_tooShortPath != null) {
      return Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: SafeArea(
          child: EmptyStatePanel(
            statusCode: 'SOUND TOO SHORT',
            title: '这段声音还没有形成可保存样本',
            description: '请继续录制至少 $_minDurationSec 秒。',
            visual: const EmptyMicPortVisual(locked: false),
            variant: EmptyStateVariant.cleared,
            primaryLabel: '重新录音',
            onPrimary: _rerunAfterShort,
            secondaryLabel: '仍然保存',
            onSecondary: _keepShortRecording,
          ),
        ),
      );
    }

    final visualActive = _ready && !_paused && _error == null;
    final canControl = _ready && _error == null && !_busy;
    final features = _recorder.featuresNotifier;
    final statusText = _error != null
        ? '录音不可用'
        : (_starting
            ? '正在启动…'
            : (_paused ? '录音已暂停' : '正在录音'));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmCancel();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _confirmCancel,
                      child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    Text(
                      statusText,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (kDebugMode)
                      TextButton(
                        onPressed: () =>
                            setState(() => _showAudioDebug = !_showAudioDebug),
                        child: Text(
                          _showAudioDebug ? 'DBG' : 'dbg',
                          style: TextStyle(
                            color: _showAudioDebug
                                ? AppColors.accent
                                : AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                  TextButton(
                    onPressed: _starting ? null : _beginRecording,
                    child: const Text('重试', style: TextStyle(color: AppColors.accent)),
                  ),
                ],
                if (_levelHint != null && _error == null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _levelHint!,
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  ),
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final side = math.min(
                        constraints.maxWidth * 0.78,
                        constraints.maxHeight * 0.88,
                      );
                      return Align(
                        alignment: const Alignment(0, -0.15),
                        child: SizedBox(
                          width: side,
                          height: side,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              SoundVisualCanvas(
                                seed: _visualSeed,
                                mode: _paused
                                    ? SoundVisualMode.paused
                                    : (visualActive
                                        ? SoundVisualMode.recording
                                        : SoundVisualMode.idle),
                                features: features,
                                liveVolume: _recorder.liveVolume,
                              ),
                              AudioDriveDebugPanel(
                                features: features,
                                visible: _showAudioDebug,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                TimerText(seconds: _seconds),
                const SizedBox(height: 6),
                SizedBox(
                  height: 12,
                  width: 8,
                  child: CustomPaint(painter: _RecordEnergyLinkPainter()),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: canControl ? _togglePause : null,
                      child: Text(
                        _paused ? '继续' : '暂停',
                        style: const TextStyle(color: AppColors.accent),
                      ),
                    ),
                    const SizedBox(width: 32),
                    RecordFab(
                      state: _paused
                          ? RecordFabState.paused
                          : (visualActive
                              ? RecordFabState.recording
                              : RecordFabState.idle),
                      onTap: canControl ? _finish : () {},
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.block),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordEnergyLinkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height),
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.12)
        ..strokeWidth = 0.7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
