import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/audio_recording_service.dart';
import '../../services/permission_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
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
  int _seconds = 0;
  bool _paused = false;
  bool _busy = false;
  String? _error;
  double _level = -45;

  @override
  void initState() {
    super.initState();
    _beginRecording();
  }

  Future<void> _beginRecording() async {
    final granted = await PermissionService.ensureMicrophone();
    if (!granted) {
      if (mounted) {
        setState(() => _error = '麦克风权限未开启');
      }
      return;
    }
    try {
      await _recorder.start();
      _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_paused && mounted) {
          setState(() => _seconds = _recorder.elapsedSeconds());
        }
      });
      _recorder.amplitudeStream.listen((amp) {
        if (mounted && !_paused) setState(() => _level = amp);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
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
    if (_paused) {
      await _recorder.resume();
    } else {
      await _recorder.pause();
    }
    setState(() => _paused = !_paused);
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _recorder.stop();
      _uiTimer?.cancel();
      if (mounted) widget.onComplete(result.path, result.durationSec);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存录音失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visualActive = !_paused && _error == null;
    final ampNorm = ((_level + 45) / 45).clamp(0.05, 1.0);
    final levelHint = _error != null
        ? null
        : (_level < -40
            ? '音量偏低，靠近声源'
            : (_level > -8 ? '音量偏高' : '音量正常'));
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
                      _error != null
                          ? '录音不可用'
                          : (_paused ? '录音已暂停' : '正在录音'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ],
                if (levelHint != null) ...[
                  const SizedBox(height: 4),
                  Text(levelHint, style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                ],
                const Spacer(),
                Expanded(
                  child: SoundVisualCanvas(
                    seed: 8801 + _seconds,
                    mode: _paused
                        ? SoundVisualMode.paused
                        : (visualActive
                            ? SoundVisualMode.recording
                            : SoundVisualMode.idle),
                    amplitude: ampNorm,
                  ),
                ),
                TimerText(seconds: _seconds),
                const SizedBox(height: AppSpacing.block),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _error != null ? null : _togglePause,
                      child: Text(
                        _paused ? '继续' : '暂停',
                        style: const TextStyle(color: AppColors.accent),
                      ),
                    ),
                    const SizedBox(width: 32),
                    RecordFab(
                      recording: visualActive && !_paused,
                      onTap: _error != null || _busy ? () {} : _finish,
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
