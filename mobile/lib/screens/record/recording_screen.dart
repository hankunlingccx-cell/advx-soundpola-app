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
    final visualActive = !_paused && _level > -50;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmCancel();
      },
      child: Scaffold(
        backgroundColor: AppColors.darkCanvas,
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
                      child: const Text('取消', style: TextStyle(color: AppColors.darkSecondary)),
                    ),
                    Text(
                      _error != null
                          ? '录音不可用'
                          : (_paused ? '录音已暂停' : '正在录音'),
                      style: const TextStyle(color: AppColors.darkText, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ],
                const Spacer(),
                Expanded(
                  child: SoundVisualCanvas(
                    seed: 8801 + _seconds,
                    active: visualActive,
                    dark: true,
                  ),
                ),
                TimerText(seconds: _seconds, dark: true),
                const SizedBox(height: AppSpacing.block),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _error != null ? null : _togglePause,
                      child: Text(
                        _paused ? '继续' : '暂停',
                        style: const TextStyle(color: AppColors.primary500),
                      ),
                    ),
                    const SizedBox(width: 32),
                    RecordFab(
                      recording: visualActive,
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
