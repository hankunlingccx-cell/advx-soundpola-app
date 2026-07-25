import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class AudioPlaybackService {
  AudioPlaybackService._() {
    // Single subscription for the lifetime of the player — fixes the prior
    // leak where each play() registered a new onPlayerComplete listener.
    _completeSub = _player.onPlayerComplete.listen((_) {
      _playing = false;
      _completionController.add(null);
    });
  }
  static final AudioPlaybackService instance = AudioPlaybackService._();

  final AudioPlayer _player = AudioPlayer();
  String? _currentPath;
  bool _playing = false;
  StreamSubscription<void>? _completeSub;

  // Broadcast so multiple screens (Memory/Result/Drafts) can listen at once.
  final _completionController = StreamController<void>.broadcast();
  Stream<void> get completionStream => _completionController.stream;
  Stream<Duration> get positionStream => _player.onPositionChanged;
  Stream<Duration> get durationStream => _player.onDurationChanged;

  bool get isPlaying => _playing;
  String? get currentPath => _currentPath;

  Future<void> play(String path) async {
    if (_playing && _currentPath == path) {
      await stop();
      return;
    }
    await _player.stop();
    _currentPath = path;
    _playing = true;
    await _player.play(DeviceFileSource(path));
    // Completion is handled by the single _completeSub registered in the ctor.
  }

  Future<void> stop() async {
    await _player.stop();
    _playing = false;
  }

  void dispose() {
    _completeSub?.cancel();
    _completionController.close();
    _player.dispose();
  }
}
