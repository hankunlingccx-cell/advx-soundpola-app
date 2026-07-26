import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 全局单一播放：任意时刻最多一段声音，切换前先停再载。
class AudioPlaybackService extends ChangeNotifier {
  AudioPlaybackService._() {
    _player.onPlayerComplete.listen((_) {
      _playing = false;
      _position = _duration;
      positionMs.value = _position.inMilliseconds;
      notifyListeners();
    });
    _player.onDurationChanged.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _player.onPositionChanged.listen((p) {
      _position = p;
      positionMs.value = p.inMilliseconds;
      notifyListeners();
    });
    _player.onPlayerStateChanged.listen((state) {
      _playing = state == PlayerState.playing;
      notifyListeners();
    });
  }

  static final AudioPlaybackService instance = AudioPlaybackService._();

  final AudioPlayer _player = AudioPlayer();
  String? _currentPath;
  bool _playing = false;
  bool _loading = false;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  /// Audio clock for [IndexedVisualPlayer] / [BakedSoundVisual].
  final ValueNotifier<int> positionMs = ValueNotifier(0);

  bool get isPlaying => _playing;
  bool get isLoading => _loading;
  String? get currentPath => _currentPath;
  String? get error => _error;
  Duration get position => _position;
  Duration get duration => _duration;

  double get progress {
    final total = _duration.inMilliseconds;
    if (total <= 0) return 0;
    return (_position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Future<void> play(String path) async {
    if (path.isEmpty) {
      _error = '无可播放音频';
      notifyListeners();
      return;
    }

    // 同一路径：播放中则暂停，暂停中则恢复
    if (_currentPath == path && !_loading) {
      if (_playing) {
        await pause();
      } else {
        await resume();
      }
      return;
    }

    await _loadAndPlay(path);
  }

  Future<void> playExclusive(String path) async {
    if (path.isEmpty) {
      _error = '无可播放音频';
      notifyListeners();
      return;
    }
    if (_currentPath == path && _playing) return;
    if (_currentPath == path && !_playing && _error == null) {
      await resume();
      return;
    }
    await _loadAndPlay(path);
  }

  Future<void> _loadAndPlay(String path) async {
    _loading = true;
    _error = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    positionMs.value = 0;
    notifyListeners();

    try {
      await _player.stop();
      _playing = false;
      _currentPath = path;
      await _player.play(DeviceFileSource(path));
      _playing = true;
      _error = null;
    } catch (e) {
      _playing = false;
      _error = '音频加载失败';
      debugPrint('AudioPlaybackService play error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
      _playing = false;
      notifyListeners();
    } catch (e) {
      debugPrint('AudioPlaybackService pause error: $e');
    }
  }

  Future<void> resume() async {
    if (_currentPath == null) return;
    if (_error != null) {
      await _loadAndPlay(_currentPath!);
      return;
    }
    try {
      await _player.resume();
      _playing = true;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = '音频加载失败';
      _playing = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    _playing = false;
    _position = Duration.zero;
    positionMs.value = 0;
    notifyListeners();
  }

  /// 切换声片前调用：平滑停下，清空当前路径，避免重叠。
  Future<void> softStop() async {
    try {
      await _player.stop();
    } catch (_) {}
    _playing = false;
    _loading = false;
    _currentPath = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    positionMs.value = 0;
    _error = null;
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
      _position = position;
      positionMs.value = position.inMilliseconds;
      notifyListeners();
    } catch (e) {
      debugPrint('AudioPlaybackService seek error: $e');
    }
  }

  Future<void> retry() async {
    final path = _currentPath;
    if (path == null || path.isEmpty) return;
    await _loadAndPlay(path);
  }

  @override
  void dispose() {
    positionMs.dispose();
    _player.dispose();
    super.dispose();
  }
}
