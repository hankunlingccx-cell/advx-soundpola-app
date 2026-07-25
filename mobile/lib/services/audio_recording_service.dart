import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../audio/audio_feature_analyzer.dart';
import '../audio/audio_features.dart';
import '../visual/audio_feature_timeline.dart';

class AudioRecordingService {
  AudioRecordingService._();
  static final AudioRecordingService instance = AudioRecordingService._();

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  DateTime? _startedAt;
  DateTime? _pausedAt;
  Duration _pausedTotal = Duration.zero;
  String? _currentPath;
  int _visualSeed = 0;
  final AudioFeatureTimeline _timeline = AudioFeatureTimeline();
  VoidCallback? _featuresListener;

  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  AudioFeatureAnalyzer? _analyzer;
  ValueNotifier<AudioFeatures>? get featuresNotifier => _analyzer?.features;
  Future<void>? _analyzerWarming;

  /// Gated + AGC'd 0–1 volume from analyzer (falls back to raw amp).
  final ValueNotifier<double> liveVolume = ValueNotifier(0.0);
  VoidCallback? _analyzerLiveListener;

  int get visualSeed => _visualSeed;
  AudioFeatureTimeline get featureTimeline => _timeline;

  /// 已成功调用 start，可暂停／完成。
  bool get isRecording => _startedAt != null;
  bool _paused = false;
  bool get isPaused => _paused;

  int _audioTimeMs() {
    if (_startedAt == null) return 0;
    var elapsed = DateTime.now().difference(_startedAt!) - _pausedTotal;
    if (_paused && _pausedAt != null) {
      elapsed -= DateTime.now().difference(_pausedAt!);
    }
    return elapsed.inMilliseconds.clamp(0, kMaxRecordingDurationSec * 1000);
  }

  Future<String> _newFilePath(String ext) async {
    final dir = await getApplicationDocumentsDirectory();
    final recordings = Directory('${dir.path}/recordings');
    if (!await recordings.exists()) {
      await recordings.create(recursive: true);
    }
    final name = 'rec_${DateTime.now().millisecondsSinceEpoch}.$ext';
    return '${recordings.path}${Platform.pathSeparator}$name';
  }

  Future<void> _ensureAnalyzer() async {
    if (_analyzer != null) return;
    if (_analyzerWarming != null) {
      await _analyzerWarming;
      return;
    }
    _analyzerWarming = () async {
      _analyzer = await AudioFeatureAnalyzer.spawn().timeout(
        const Duration(seconds: 4),
        onTimeout: () => throw TimeoutException('音高分析器启动超时'),
      );
      _analyzerLiveListener = () {
        liveVolume.value = math.max(
          liveVolume.value,
          _analyzer!.liveVolume.value,
        );
      };
      _analyzer!.liveVolume.addListener(_analyzerLiveListener!);
    }();
    try {
      await _analyzerWarming;
    } finally {
      _analyzerWarming = null;
    }
  }

  /// Prefetch isolate on Record home so first tap isn't waiting on spawn.
  Future<void> warmUp() async {
    try {
      await _ensureAnalyzer();
    } catch (e) {
      debugPrint('[Rec] warmUp analyzer failed: $e');
    }
  }

  void _bindAnalyzerWhileRecording() {
    if (_analyzer == null || !isRecording) return;
    if (_featuresListener != null) return;
    _analyzer!.setActive(!_paused);
    _featuresListener = () {
      if (_paused || _analyzer == null) return;
      _timeline.add(_audioTimeMs(), _analyzer!.features.value);
    };
    _analyzer!.features.addListener(_featuresListener!);
  }

  Future<void> start({int? visualSeed}) async {
    if (isRecording) {
      await cancel();
    }
    if (!await _recorder.hasPermission()) {
      throw StateError('麦克风权限未授予');
    }

    _visualSeed = visualSeed ??
        (DateTime.now().millisecondsSinceEpoch % 900000) + 1000;
    _timeline.clear();

    // Kick analyzer in background — never block mic ready on Isolate.spawn.
    unawaited(
      _ensureAnalyzer().then((_) {
        _bindAnalyzerWhileRecording();
      }).catchError((Object e) {
        debugPrint('[Rec] analyzer spawn failed: $e');
      }),
    );

    // Primary path = previous known-good AAC file recording.
    // Avoid startStream(pcm16): on some Android devices the native
    // RecordThread CountDownLatch never releases → UI stuck on「正在启动」.
    final path = await _newFilePath('m4a');
    _currentPath = path;

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 48000,
          autoGain: true,
          noiseSuppress: false,
        ),
        path: path,
      );
      debugPrint('[Rec] AAC recording started');
    } catch (e) {
      _currentPath = null;
      rethrow;
    }

    _startedAt = DateTime.now();
    _paused = false;
    _pausedTotal = Duration.zero;
    _bindAnalyzerWhileRecording();

    _ampSub?.cancel();
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 16))
        .listen((amp) {
      final v = amp.current;
      _amplitudeController.add(v);
      final n = (v <= 1.0 && v >= 0.0) ? v : ((v + 60) / 60).clamp(0.0, 1.0);
      // Always publish a responsive level for the canvas (even if AGC lags).
      final gated = _analyzer?.liveVolume.value;
      liveVolume.value = math.max(n, gated ?? 0);
      _analyzer?.pushAmplitude(v);
    });
  }

  Future<void> pause() async {
    if (!_paused && _startedAt != null) {
      await _recorder.pause();
      _paused = true;
      _pausedAt = DateTime.now();
      _analyzer?.setActive(false);
      liveVolume.value = 0;
    }
  }

  Future<void> resume() async {
    if (_paused && _pausedAt != null) {
      _pausedTotal += DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      await _recorder.resume();
      _paused = false;
      _analyzer?.setActive(true);
    }
  }

  Future<
      ({
        String path,
        int durationSec,
        int visualSeed,
        AudioFeatureTimeline timeline,
      })> stop() async {
    if (_startedAt == null && _currentPath == null) {
      throw StateError('录音尚未开始');
    }

    String? stoppedPath;
    try {
      stoppedPath = await _recorder.stop();
    } catch (e) {
      debugPrint('AudioRecordingService stop error: $e');
    }

    await _ampSub?.cancel();
    _ampSub = null;
    if (_featuresListener != null) {
      _analyzer?.features.removeListener(_featuresListener!);
      _featuresListener = null;
    }
    _analyzer?.setActive(false);
    liveVolume.value = 0;

    final end = DateTime.now();
    final started = _startedAt ?? end;
    var duration = end.difference(started) - _pausedTotal;
    if (_paused && _pausedAt != null) {
      duration -= DateTime.now().difference(_pausedAt!);
    }
    final sec = duration.inSeconds.clamp(1, kMaxRecordingDurationSec);

    final candidate = _firstNonEmpty(stoppedPath, _currentPath);
    final seed = _visualSeed;
    final timeline = AudioFeatureTimeline(
      samples: List<AudioFeatureSample>.from(_timeline.samples),
    );
    _startedAt = null;
    _paused = false;
    _pausedAt = null;
    _pausedTotal = Duration.zero;
    _timeline.clear();

    if (candidate == null) {
      _currentPath = null;
      throw StateError('录音文件路径无效');
    }

    final file = File(candidate);
    final ready = await _waitForFile(file);
    _currentPath = null;
    if (!ready) {
      throw StateError('录音文件未生成');
    }
    return (
      path: candidate,
      durationSec: sec,
      visualSeed: seed,
      timeline: timeline,
    );
  }

  static String? _firstNonEmpty(String? a, String? b) {
    if (a != null && a.isNotEmpty) return a;
    if (b != null && b.isNotEmpty) return b;
    return null;
  }

  Future<bool> _waitForFile(File file, {int attempts = 8}) async {
    for (var i = 0; i < attempts; i++) {
      if (await file.exists()) {
        final len = await file.length();
        if (len > 0) return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  Future<void> cancel() async {
    try {
      await _recorder.stop();
    } catch (_) {}
    await _ampSub?.cancel();
    _ampSub = null;
    if (_featuresListener != null) {
      _analyzer?.features.removeListener(_featuresListener!);
      _featuresListener = null;
    }
    _analyzer?.setActive(false);
    liveVolume.value = 0;
    _timeline.clear();
    final path = _currentPath;
    _currentPath = null;
    if (path != null) {
      final f = File(path);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    _startedAt = null;
    _paused = false;
    _pausedAt = null;
    _pausedTotal = Duration.zero;
  }

  int elapsedSeconds() {
    if (_startedAt == null) return 0;
    var elapsed = DateTime.now().difference(_startedAt!) - _pausedTotal;
    if (_paused && _pausedAt != null) {
      elapsed -= DateTime.now().difference(_pausedAt!);
    }
    return elapsed.inSeconds;
  }

  void dispose() {
    _ampSub?.cancel();
    if (_featuresListener != null) {
      _analyzer?.features.removeListener(_featuresListener!);
      _featuresListener = null;
    }
    if (_analyzerLiveListener != null) {
      _analyzer?.liveVolume.removeListener(_analyzerLiveListener!);
      _analyzerLiveListener = null;
    }
    _amplitudeController.close();
    liveVolume.dispose();
    _analyzer?.dispose();
    _analyzer = null;
    _recorder.dispose();
  }
}
