import 'dart:math' as math;

/// Built-in one-shot beat sample kinds (no AI PCM generation).
enum BeatType {
  kick,
  snare,
  clap,
  closedHat,
  click,
  glitch;

  String get assetPath => switch (this) {
        BeatType.kick => 'assets/beats/kick.wav',
        BeatType.snare => 'assets/beats/snare.wav',
        BeatType.clap => 'assets/beats/clap.wav',
        BeatType.closedHat => 'assets/beats/closed_hat.wav',
        BeatType.click => 'assets/beats/click.wav',
        BeatType.glitch => 'assets/beats/glitch.wav',
      };

  String get label => switch (this) {
        BeatType.kick => 'Kick',
        BeatType.snare => 'Snare',
        BeatType.clap => 'Clap',
        BeatType.closedHat => 'Hat',
        BeatType.click => 'Click',
        BeatType.glitch => 'Glitch',
      };

  static BeatType? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final key = raw.trim().toLowerCase().replaceAll('-', '_');
    return switch (key) {
      'kick' => BeatType.kick,
      'snare' => BeatType.snare,
      'clap' => BeatType.clap,
      'closed_hat' || 'closedhat' || 'hat' => BeatType.closedHat,
      'click' => BeatType.click,
      'glitch' => BeatType.glitch,
      _ => null,
    };
  }

  String get wireName => switch (this) {
        BeatType.closedHat => 'closed_hat',
        _ => name,
      };
}

enum BeatDensity {
  sparse,
  balanced,
  dense;

  String get label => switch (this) {
        BeatDensity.sparse => '稀疏',
        BeatDensity.balanced => '平衡',
        BeatDensity.dense => '密集',
      };

  static BeatDensity parse(String? raw) {
    final key = (raw ?? '').trim().toLowerCase();
    return switch (key) {
      'sparse' || '稀疏' => BeatDensity.sparse,
      'dense' || '密集' => BeatDensity.dense,
      _ => BeatDensity.balanced,
    };
  }
}

enum BeatStyle {
  minimal,
  groove,
  glitch;

  String get label => switch (this) {
        BeatStyle.minimal => 'Minimal',
        BeatStyle.groove => 'Groove',
        BeatStyle.glitch => 'Glitch',
      };

  static BeatStyle parse(String? raw) {
    final key = (raw ?? '').trim().toLowerCase();
    return switch (key) {
      'groove' => BeatStyle.groove,
      'glitch' => BeatStyle.glitch,
      _ => BeatStyle.minimal,
    };
  }
}

enum LabSourceKind { session, draft, collection }

class LabSoundSource {
  const LabSoundSource({
    required this.id,
    required this.kind,
    required this.title,
    required this.audioPath,
    required this.durationMs,
    this.coverSeed = 0,
    this.featuresPath,
    this.coverPath,
    this.memoryId,
  });

  final String id;
  final LabSourceKind kind;
  final String title;
  final String audioPath;
  final int durationMs;
  final int coverSeed;
  final String? featuresPath;
  final String? coverPath;
  final String? memoryId;

  String get kindLabel => switch (kind) {
        LabSourceKind.session => '当前录音',
        LabSourceKind.draft => 'Drafts',
        LabSourceKind.collection => 'Collection',
      };
}

/// Canvas placement for a source (max 4).
class LabCanvasNode {
  LabCanvasNode({
    required this.source,
    required this.nx,
    required this.ny,
    this.isPrimary = false,
    this.muted = false,
  });

  final LabSoundSource source;

  /// Normalized canvas coords in [-1, 1]; (0,0) = listener core.
  double nx;
  double ny;
  bool isPrimary;
  bool muted;

  /// Distance from center → volume (near = loud).
  double get volume {
    final d = math.sqrt(nx * nx + ny * ny).clamp(0.0, 1.414);
    final t = (1.0 - d / 1.414).clamp(0.0, 1.0);
    return 0.12 + t * 0.88;
  }

  /// Left/right pan from nx (−1 left … +1 right).
  double get pan => nx.clamp(-1.0, 1.0);
}

class BeatEvent {
  BeatEvent({
    required this.id,
    required this.timeMs,
    required this.sourceIndex,
    required this.playDurationMs,
    this.sliceOffsetMs = 0,
    this.strength = 0.8,
    this.volume = 0.85,
    this.pan = 0,
    this.generated = true,
    this.isDownbeat = false,
    /// 兼容旧字段；轮播模式下可忽略。
    this.type = BeatType.click,
    this.sampleAsset = '',
  });

  final String id;

  /// 轮播触发时间（相对混音时间轴）。
  int timeMs;

  /// 播放哪一段已选声音（0-based，对应画布顺序）。
  int sourceIndex;

  /// 本拍持续时长（通常 = 1 拍）。
  int playDurationMs;

  /// 从该声音的何处起播（切片起点）。
  int sliceOffsetMs;

  double strength;
  double volume;
  double pan;
  bool generated;
  bool isDownbeat;
  BeatType type;
  String sampleAsset;

  BeatEvent copyWith({
    int? timeMs,
    int? sourceIndex,
    int? playDurationMs,
    int? sliceOffsetMs,
    double? strength,
    double? volume,
    double? pan,
    bool? generated,
    bool? isDownbeat,
    BeatType? type,
    String? sampleAsset,
  }) {
    return BeatEvent(
      id: id,
      timeMs: timeMs ?? this.timeMs,
      sourceIndex: sourceIndex ?? this.sourceIndex,
      playDurationMs: playDurationMs ?? this.playDurationMs,
      sliceOffsetMs: sliceOffsetMs ?? this.sliceOffsetMs,
      strength: strength ?? this.strength,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      generated: generated ?? this.generated,
      isDownbeat: isDownbeat ?? this.isDownbeat,
      type: type ?? this.type,
      sampleAsset: sampleAsset ?? this.sampleAsset,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timeMs': timeMs,
        'sourceIndex': sourceIndex,
        'playDurationMs': playDurationMs,
        'sliceOffsetMs': sliceOffsetMs,
        'strength': strength,
        'volume': volume,
        'pan': pan,
        'generated': generated,
        'isDownbeat': isDownbeat,
      };

  factory BeatEvent.fromJson(Map<String, dynamic> j, {int index = 0}) {
    final type = BeatType.tryParse(j['type']?.toString()) ?? BeatType.click;
    return BeatEvent(
      id: j['id']?.toString() ?? 'evt_$index',
      timeMs: (j['timeMs'] as num?)?.round() ?? 0,
      sourceIndex: (j['sourceIndex'] as num?)?.round() ??
          (j['trackIndex'] as num?)?.round() ??
          0,
      playDurationMs: (j['playDurationMs'] as num?)?.round() ??
          (j['durationMs'] as num?)?.round() ??
          500,
      sliceOffsetMs: (j['sliceOffsetMs'] as num?)?.round() ?? 0,
      strength: ((j['strength'] as num?)?.toDouble() ?? 0.8).clamp(0.0, 1.0),
      volume: ((j['volume'] as num?)?.toDouble() ?? 0.85).clamp(0.0, 1.0),
      pan: ((j['pan'] as num?)?.toDouble() ?? 0.0).clamp(-1.0, 1.0),
      generated: j['generated'] as bool? ?? true,
      isDownbeat: j['isDownbeat'] as bool? ?? false,
      type: type,
      sampleAsset: j['sampleAsset']?.toString() ?? '',
    );
  }
}

class BeatPlan {
  BeatPlan({
    required this.id,
    required this.sourceSoundId,
    required this.estimatedBpm,
    required this.seed,
    required this.generatorVersion,
    required this.events,
    this.style = BeatStyle.minimal,
    this.density = BeatDensity.balanced,
  });

  final String id;
  final String sourceSoundId;
  final double estimatedBpm;
  final int seed;
  final String generatorVersion;
  final List<BeatEvent> events;
  final BeatStyle style;
  final BeatDensity density;

  static const generatorVersionLocal = 'local_rotate_planner_v1';
  static const generatorVersionCodex = 'codex_rotate_plan_v1';

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceSoundId': sourceSoundId,
        'bpm': estimatedBpm,
        'estimatedBpm': estimatedBpm,
        'seed': seed,
        'generatorVersion': generatorVersion,
        'style': style.name,
        'density': density.name,
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory BeatPlan.fromJson(Map<String, dynamic> j) {
    final rawEvents = j['events'];
    final list = <BeatEvent>[];
    if (rawEvents is List) {
      for (var i = 0; i < rawEvents.length; i++) {
        final item = rawEvents[i];
        if (item is Map<String, dynamic>) {
          list.add(BeatEvent.fromJson(item, index: i));
        } else if (item is Map) {
          list.add(BeatEvent.fromJson(Map<String, dynamic>.from(item), index: i));
        }
      }
    }
    final bpm = (j['bpm'] as num?)?.toDouble() ??
        (j['estimatedBpm'] as num?)?.toDouble() ??
        90.0;
    return BeatPlan(
      id: j['id']?.toString() ?? 'plan_${DateTime.now().millisecondsSinceEpoch}',
      sourceSoundId: j['sourceSoundId']?.toString() ?? '',
      estimatedBpm: bpm,
      seed: (j['seed'] as num?)?.round() ?? 0,
      generatorVersion:
          j['generatorVersion']?.toString() ?? generatorVersionCodex,
      events: list,
      style: BeatStyle.parse(j['style']?.toString()),
      density: BeatDensity.parse(j['density']?.toString()),
    );
  }
}

class EnergySegment {
  const EnergySegment({
    required this.startMs,
    required this.endMs,
    required this.energy,
  });

  final int startMs;
  final int endMs;
  final double energy;

  Map<String, dynamic> toJson() => {
        'startMs': startMs,
        'endMs': endMs,
        'energy': energy,
      };

  factory EnergySegment.fromJson(Map<String, dynamic> j) => EnergySegment(
        startMs: (j['startMs'] as num?)?.round() ?? 0,
        endMs: (j['endMs'] as num?)?.round() ?? 0,
        energy: (j['energy'] as num?)?.toDouble() ?? 0,
      );
}

class SilenceRange {
  const SilenceRange({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;

  Map<String, dynamic> toJson() => {
        'startMs': startMs,
        'endMs': endMs,
      };

  factory SilenceRange.fromJson(Map<String, dynamic> j) => SilenceRange(
        startMs: (j['startMs'] as num?)?.round() ?? 0,
        endMs: (j['endMs'] as num?)?.round() ?? 0,
      );
}

/// 单段声音中音量最高的有效片段（轮播前截取）。
class HotClip {
  const HotClip({
    required this.startMs,
    required this.durationMs,
    this.peakEnergy = 0,
  });

  final int startMs;
  final int durationMs;
  final double peakEnergy;

  int get endMs => startMs + durationMs;

  Map<String, dynamic> toJson() => {
        'startMs': startMs,
        'durationMs': durationMs,
        'peakEnergy': peakEnergy,
      };

  factory HotClip.fromJson(Map<String, dynamic> j) => HotClip(
        startMs: (j['startMs'] as num?)?.round() ?? 0,
        durationMs: (j['durationMs'] as num?)?.round() ?? 500,
        peakEnergy: (j['peakEnergy'] as num?)?.toDouble() ?? 0,
      );
}

/// Structured audio features for Codex / local BeatPlanner (never full PCM).
class FeatureSummary {
  FeatureSummary({
    required this.durationMs,
    required this.estimatedBpm,
    required this.onsetsMs,
    required this.energySegments,
    required this.silenceRanges,
    required this.requestedStyle,
    required this.requestedDensity,
    this.beatGridMs = const [],
    this.candidateBeatMs = const [],
    this.sourceSoundId = '',
    this.sourceCount = 1,
    this.sourceDurationsMs = const [],
    this.sourceHotClips = const [],
  });

  final int durationMs;
  final double estimatedBpm;
  final List<int> onsetsMs;
  final List<EnergySegment> energySegments;
  final List<SilenceRange> silenceRanges;
  final String requestedStyle;
  final String requestedDensity;
  final List<int> beatGridMs;
  final List<int> candidateBeatMs;
  final String sourceSoundId;

  /// 已选声音数量（轮播用）。
  final int sourceCount;

  /// 各选中声音时长，与画布顺序一致。
  final List<int> sourceDurationsMs;

  /// 各选中声音的最高音量有效片段（与画布顺序一致）。
  final List<HotClip> sourceHotClips;

  Map<String, dynamic> toJson() => {
        'durationMs': durationMs,
        'estimatedBpm': estimatedBpm,
        'onsetsMs': onsetsMs,
        'energySegments': energySegments.map((e) => e.toJson()).toList(),
        'silenceRanges': silenceRanges.map((e) => e.toJson()).toList(),
        'requestedStyle': requestedStyle,
        'requestedDensity': requestedDensity,
        'beatGridMs': beatGridMs,
        'candidateBeatMs': candidateBeatMs,
        'sourceSoundId': sourceSoundId,
        'sourceCount': sourceCount,
        'sourceDurationsMs': sourceDurationsMs,
        'sourceHotClips': sourceHotClips.map((e) => e.toJson()).toList(),
      };
}
