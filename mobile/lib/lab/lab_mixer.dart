import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'beat_models.dart';

class _ActiveVoice {
  _ActiveVoice({
    required this.sourceId,
    required this.playerKey,
    required this.untilMs,
  });

  final String sourceId;
  final String playerKey;
  final int untilMs;
}

/// 阿卡贝拉混音：按时触发多源，最多同时 2 层。
class LabMixer extends ChangeNotifier {
  LabMixer();

  /// 主播放器：每个 sourceId 一个。
  final Map<String, AudioPlayer> _primary = {};

  /// 叠唱备用池（同源冲突或第二层）。
  final List<AudioPlayer> _pool = [];
  final Map<String, AudioPlayer> _borrowed = {};

  Timer? _clock;
  int _playheadMs = 0;
  int _durationMs = 0;
  bool _playing = false;
  DateTime? _startedAt;
  int _startedPlayhead = 0;
  List<BeatEvent> _beats = const [];
  List<LabCanvasNode> _nodes = const [];
  int _nextBeatIndex = 0;
  final List<_ActiveVoice> _active = [];

  static const maxLayers = 2;

  int get playheadMs => _playheadMs;
  int get durationMs => _durationMs;
  bool get isPlaying => _playing;
  String? get activeSourceId =>
      _active.isEmpty ? null : _active.last.sourceId;

  Future<void> ensureSource(LabCanvasNode node) async {
    final id = node.source.id;
    if (_primary.containsKey(id)) return;
    final p = AudioPlayer();
    await p.setReleaseMode(ReleaseMode.stop);
    await p.setVolume(node.muted ? 0 : node.volume);
    await p.setBalance(node.pan);
    _primary[id] = p;
  }

  Future<void> applySpatial(LabCanvasNode node) async {
    final p = _primary[node.source.id];
    if (p == null) return;
    await p.setVolume(node.muted ? 0 : node.volume);
    await p.setBalance(node.pan);
  }

  Future<void> removeSource(String id) async {
    final p = _primary.remove(id);
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

  /// 兼容旧调用名。
  Future<void> playRotate({
    required List<LabCanvasNode> nodes,
    required List<BeatEvent> beats,
    required int durationMs,
    int startMs = 0,
  }) =>
      playAcapella(
        nodes: nodes,
        beats: beats,
        durationMs: durationMs,
        startMs: startMs,
      );

  /// 阿卡贝拉播放：允许多事件重叠（≤2 层）。
  Future<void> playAcapella({
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
    _beats = [...beats]..sort((a, b) {
        final c = a.timeMs.compareTo(b.timeMs);
        if (c != 0) return c;
        return a.role.index.compareTo(b.role.index);
      });
    _nextBeatIndex = _beats.indexWhere((e) => e.timeMs >= _playheadMs);
    if (_nextBeatIndex < 0) _nextBeatIndex = _beats.length;
    _active.clear();

    for (final n in nodes) {
      await ensureSource(n);
      await applySpatial(n);
      try {
        await _primary[n.source.id]!.stop();
      } catch (_) {}
    }

    // 补播当前时间窗内已开始的事件
    for (final e in _beats) {
      if (e.timeMs <= _playheadMs &&
          e.timeMs + e.playDurationMs > _playheadMs) {
        await _trigger(e);
      }
    }
    _nextBeatIndex = _beats.indexWhere((e) => e.timeMs > _playheadMs);
    if (_nextBeatIndex < 0) _nextBeatIndex = _beats.length;

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
      await _trigger(_beats[_nextBeatIndex++]);
    }
    // 到期停止
    final still = <_ActiveVoice>[];
    for (final v in _active) {
      if (_playheadMs >= v.untilMs) {
        await _stopVoice(v);
      } else {
        still.add(v);
      }
    }
    _active
      ..clear()
      ..addAll(still);
  }

  Future<void> _trigger(BeatEvent ev) async {
    if (_nodes.isEmpty) return;

    // 层数限制：已满则跳过（pad/perc 优先被挤掉——调用方已排序 lead 在前）
    _active.removeWhere((v) => _playheadMs >= v.untilMs);
    if (_active.length >= maxLayers) {
      // 尝试挤掉已过期；仍满则丢弃低优先级
      if (ev.role == AcapellaRole.pad || ev.role == AcapellaRole.percussion) {
        return;
      }
      // lead/response：挤掉一个 pad/perc
      final weak = _active.indexWhere((v) {
        // 无法从 voice 反查 role，按后进弱层挤掉最后一个非 lead 源若可能
        return true;
      });
      if (_active.length >= maxLayers && weak >= 0) {
        // 挤掉最后一个
        final dropped = _active.removeLast();
        await _stopVoice(dropped);
      }
      if (_active.length >= maxLayers) return;
    }

    final idx = ev.sourceIndex.clamp(0, _nodes.length - 1);
    final node = _nodes[idx];
    final id = node.source.id;

    // 同源：若主播放器正忙，用 pool
    final primaryBusy = _active.any((v) => v.sourceId == id);
    final playerKey = primaryBusy ? 'pool_${id}_${ev.id}' : id;
    final player = primaryBusy
        ? await _acquirePool(playerKey)
        : _primary[id];
    if (player == null) return;

    final spatialVol = node.muted ? 0.0 : node.volume;
    final vol = (spatialVol * ev.volume).clamp(0.0, 1.0);
    final pan = ((node.pan + ev.pan) / 2).clamp(-1.0, 1.0);

    try {
      await player.setVolume(vol);
      await player.setBalance(pan);
      await player.stop();
      await player.setSource(DeviceFileSource(node.source.audioPath));
      final offset = ev.sliceOffsetMs
          .clamp(0, math.max(0, node.source.durationMs - 50))
          .toInt();
      await player.seek(Duration(milliseconds: offset));
      await player.resume();
      _active.add(
        _ActiveVoice(
          sourceId: id,
          playerKey: playerKey,
          untilMs: ev.timeMs + ev.playDurationMs,
        ),
      );
    } catch (e) {
      debugPrint('LabMixer acapella trigger error: $e');
    }
  }

  Future<AudioPlayer> _acquirePool(String key) async {
    final existing = _borrowed[key];
    if (existing != null) return existing;
    AudioPlayer? free;
    for (final p in _pool) {
      if (!_borrowed.containsValue(p) && p.state != PlayerState.playing) {
        free = p;
        break;
      }
    }
    if (free == null) {
      free = AudioPlayer();
      await free.setReleaseMode(ReleaseMode.stop);
      _pool.add(free);
      if (_pool.length > 6) {
        final old = _pool.removeAt(0);
        _borrowed.removeWhere((_, v) => v == old);
        await old.dispose();
      }
    }
    _borrowed[key] = free;
    return free;
  }

  Future<void> _stopVoice(_ActiveVoice v) async {
    try {
      if (v.playerKey == v.sourceId) {
        await _primary[v.sourceId]?.pause();
      } else {
        final p = _borrowed.remove(v.playerKey);
        await p?.pause();
      }
    } catch (_) {}
  }

  Future<void> stop({bool resetPlayhead = true}) async {
    _clock?.cancel();
    _clock = null;
    _playing = false;
    _startedAt = null;
    for (final v in List.of(_active)) {
      await _stopVoice(v);
    }
    _active.clear();
    for (final p in _primary.values) {
      try {
        await p.pause();
      } catch (_) {}
    }
    for (final p in _pool) {
      try {
        await p.pause();
      } catch (_) {}
    }
    _borrowed.clear();
    if (resetPlayhead) _playheadMs = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _clock?.cancel();
    for (final p in _primary.values) {
      p.dispose();
    }
    for (final p in _pool) {
      p.dispose();
    }
    super.dispose();
  }
}
