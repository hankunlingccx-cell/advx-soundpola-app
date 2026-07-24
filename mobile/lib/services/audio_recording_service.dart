import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../audio/audio_feature_analyzer.dart';
import '../audio/audio_features.dart';

class AudioRecordingService {
  AudioRecordingService._();
  static final AudioRecordingService instance = AudioRecordingService._();

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  DateTime? _startedAt;
  DateTime? _pausedAt;
  Duration _pausedTotal = Duration.zero;
  String? _currentPath;

  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  AudioFeatureAnalyzer? _analyzer;
  ValueNotifier<AudioFeatures>? get featuresNotifier => _analyzer?.features;

  bool get isRecording => _startedAt != null;
  bool _paused = false;
  bool get isPaused => _paused;

  Future<String> _newFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    final recordings = Directory('${dir.path}/recordings');
    if (!await recordings.exists()) {
      await recordings.create(recursive: true);
    }
    final name = 'rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    return '${recordings.path}/$name';
  }

  Future<void> _ensureAnalyzer() async {
    _analyzer ??= await AudioFeatureAnalyzer.spawn();
  }

  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('麦克风权限未授予');
    }
    await _ensureAnalyzer();
    _currentPath = await _newFilePath();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _currentPath!,
    );
    _startedAt = DateTime.now();
    _paused = false;
    _pausedTotal = Duration.zero;
    _analyzer!.setActive(true);
    _ampSub?.cancel();
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 40))
        .listen((amp) {
      _amplitudeController.add(amp.current);
      _analyzer?.pushAmplitude(amp.current);
    });
  }

  Future<void> pause() async {
    if (!_paused && _startedAt != null) {
      await _recorder.pause();
      _paused = true;
      _pausedAt = DateTime.now();
      _analyzer?.setActive(false);
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

  Future<({String path, int durationSec})> stop() async {
    final path = await _recorder.stop();
    await _ampSub?.cancel();
    _ampSub = null;
    _analyzer?.setActive(false);
    final end = DateTime.now();
    final started = _startedAt ?? end;
    var duration = end.difference(started) - _pausedTotal;
    if (_paused && _pausedAt != null) {
      duration -= DateTime.now().difference(_pausedAt!);
    }
    final sec = duration.inSeconds.clamp(1, 9999);
    _startedAt = null;
    _paused = false;
    _pausedAt = null;
    _pausedTotal = Duration.zero;
    final resultPath = path ?? _currentPath;
    if (resultPath == null) {
      throw StateError('录音文件路径无效');
    }
    return (path: resultPath, durationSec: sec);
  }

  Future<void> cancel() async {
    await _recorder.stop();
    await _ampSub?.cancel();
    _ampSub = null;
    _analyzer?.setActive(false);
    if (_currentPath != null) {
      final f = File(_currentPath!);
      if (await f.exists()) await f.delete();
    }
    _currentPath = null;
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
    _amplitudeController.close();
    _analyzer?.dispose();
    _analyzer = null;
    _recorder.dispose();
  }
}
