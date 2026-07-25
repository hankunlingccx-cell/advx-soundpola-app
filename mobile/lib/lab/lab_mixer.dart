import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'beat_models.dart';

/// 按 BeatPlan 轮播已选声音：到拍点切换到对应 sourceIndex。
class LabMixer extends ChangeNotifier {
  LabMixer();

  final Map<String, AudioPlayer> _sourcePlayers = {};
  Timer? _clock;
  int _playheadMs = 0;
  int _durationMs = 0;
  bool _playing = false;
  DateTime? _startedAt;
  int _startedPlayhead = 0;
  List<BeatEvent> _beats = const [];
  List<LabCanvasNode> _nodes = const [];
  int _nextBeatIndex = 0;
  String? _activeSourceId;
  int _activeUntilMs = 0;

  int get playheadMs => _playheadMs;
  int get durationMs => _durationMs;
  bool get isPlaying => _playing;
  String? get activeSourceId => _activeSourceId;

  Future<void> ensureSource(LabCanvasNode node) async {
    final id = node.source.id;
    if (_sourcePlayers.containsKey(id)) return;
    final p = AudioPlayer();
    await p.setReleaseMode(ReleaseMode.stop);
    await p.setVolume(node.muted ? 0 : node.volume);
    await p.setBalance(node.pan);
    _sourcePlayers[id] = p;
  }

  Future<void> applySpatial(LabCanvasNode node) async {
    final p = _sourcePlayers[node.source.id];
    if (p == null) return;
    await p.setVolume(node.muted ? 0 : node.volume);
    await p.setBalance(node.pan);
  }

  Future<void> removeSource(String id) async {
    final p = _sourcePlayers.remove(id);
    await p?.stop();
    await p?.dispose();
  }

  Future<void> previewSolo(String path) async {
    await stop();
    final p = AudioPlayer();
    try {
      await p.play(DeviceFileSource(path));
      await p.onPlayerComplete.first.timeout(const Duration(seconds: 90));
    } catch (_) {
    } finally {
      await p.dispose();
    }
  }

  /// 按节拍轮播：同一时刻只播一个选中声音。
  Future<void> playRotate({
    required List<LabCanvasNode> nodes,
    required List<BeatEvent> beats,
    required int durationMs,
    int startMs = 0,
  }) async {
    await stop(resetPlayhead: false);
    if (nodes.isEmpty) return;

    _nodes = List.of(nodes);
    _durationMs = math.max(durationMs, 1000);
    _playheadMs = startMs.clamp(0, _durationMs);
    _beats = [...beats]..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    _nextBeatIndex = _beats.indexWhere((e) => e.timeMs >= _playheadMs);
    if (_nextBeatIndex < 0) _nextBeatIndex = _beats.length;
    _activeSourceId = null;
    _activeUntilMs = 0;

    for (final n in nodes) {
      await ensureSource(n);
      await applySpatial(n);
      try {
        await _sourcePlayers[n.source.id]!.stop();
      } catch (_) {}
    }

    // 若起始落在某拍中间，立即切入该拍
    BeatEvent? current;
    for (final e in _beats) {
      if (e.timeMs <= _playheadMs &&
          e.timeMs + e.playDurationMs > _playheadMs) {
        current = e;
      }
    }
    if (current != null) {
      await _activate(current);
      _nextBeatIndex = _beats.indexWhere((e) => e.timeMs > current!.timeMs);
      if (_nextBeatIndex < 0) _nextBeatIndex = _beats.length;
    } else if (_beats.isNotEmpty && _playheadMs <= _beats.first.timeMs) {
      // 等第一拍
    } else if (_beats.isEmpty) {
      // 无计划：顺序轮播兜底
      await _activate(
        BeatEvent(
          id: 'fallback',
          timeMs: 0,
          sourceIndex: 0,
          playDurationMs: _durationMs,
        ),
      );
    }

    _playing = true;
    _startedAt = DateTime.now();
    _startedPlayhead = _playheadMs;
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_playing || _startedAt == null) return;
      final elapsed = DateTime.now().difference(_startedAt!).inMilliseconds;
      _playheadMs = (_startedPlayhead + elapsed).clamp(0, _durationMs);
      unawaited(_tick());
      notifyListeners();
      if (_playheadMs >= _durationMs) {
        stop();
      }
    });
    notifyListeners();
  }

  Future<void> _tick() async {
    while (_nextBeatIndex < _beats.length &&
        _beats[_nextBeatIndex].timeMs <= _playheadMs) {
      final ev = _beats[_nextBeatIndex++];
      await _activate(ev);
    }
    // 拍时结束则停
    if (_activeSourceId != null && _playheadMs >= _activeUntilMs) {
      final p = _sourcePlayers[_activeSourceId!];
      try {
        await p?.pause();
      } catch (_) {}
    }
  }

  Future<void> _activate(BeatEvent ev) async {
    if (_nodes.isEmpty) return;
    final idx = ev.sourceIndex.clamp(0, _nodes.length - 1);
    final node = _nodes[idx];
    final id = node.source.id;

    // 停掉其他源
    for (final entry in _sourcePlayers.entries) {
      if (entry.key == id) continue;
      try {
        await entry.value.pause();
      } catch (_) {}
    }

    final p = _sourcePlayers[id];
    if (p == null) return;

    final vol = (node.muted ? 0.0 : node.volume) * ev.volume;
    final pan = ((node.pan + ev.pan) / 2).clamp(-1.0, 1.0);
    try {
      await p.setVolume(vol);
      await p.setBalance(pan);
      await p.stop();
      await p.setSource(DeviceFileSource(node.source.audioPath));
      final offset = ev.sliceOffsetMs
          .clamp(0, math.max(0, node.source.durationMs - 50))
          .toInt();
      await p.seek(Duration(milliseconds: offset));
      await p.resume();
      _activeSourceId = id;
      _activeUntilMs = ev.timeMs + ev.playDurationMs;
    } catch (e) {
      debugPrint('LabMixer rotate activate error: $e');
    }
  }

  Future<void> stop({bool resetPlayhead = true}) async {
    _clock?.cancel();
    _clock = null;
    _playing = false;
    _startedAt = null;
    _activeSourceId = null;
    for (final p in _sourcePlayers.values) {
      try {
        await p.pause();
      } catch (_) {}
    }
    if (resetPlayhead) _playheadMs = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _clock?.cancel();
    for (final p in _sourcePlayers.values) {
      p.dispose();
    }
    super.dispose();
  }
}
