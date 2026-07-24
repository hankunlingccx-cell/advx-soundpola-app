import 'package:audioplayers/audioplayers.dart';

class AudioPlaybackService {
  AudioPlaybackService._();
  static final AudioPlaybackService instance = AudioPlaybackService._();

  final AudioPlayer _player = AudioPlayer();
  String? _currentPath;
  bool _playing = false;

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
    _player.onPlayerComplete.listen((_) {
      _playing = false;
    });
  }

  Future<void> stop() async {
    await _player.stop();
    _playing = false;
  }

  void dispose() {
    _player.dispose();
  }
}
