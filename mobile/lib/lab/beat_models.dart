import 'dart:math' as math;

/// Built-in one-shot kinds（兼容旧字段；阿卡贝拉编排可忽略）。
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

/// 阿卡贝拉声部角色（按选中顺序自动赋，可被 AI 覆盖）。
enum AcapellaRole {
  /// 主声 / 主句
  lead,

  /// 应答 / 呼应
  response,

  /// 衬底叠唱（音量偏低）
  pad,

  /// 节奏向短切片
  percussion;

  String get label => switch (this) {
        AcapellaRole.lead => '主声',
        AcapellaRole.response => '应答',
        AcapellaRole.pad => '衬底',
        AcapellaRole.percussion => '节奏',
      };

  static AcapellaRole parse(String? raw) {
    final key = (raw ?? '').trim().toLowerCase();
    return switch (key) {
      'response' || '应答' => AcapellaRole.response,
      'pad' || '衬底' => AcapellaRole.pad,
      'percussion' || 'perc' || '节奏' => AcapellaRole.percussion,
      _ => AcapellaRole.lead,
    };
  }

  /// 按画布顺序默认赋角色：0 lead → 1 response → 2 pad → 3+ percussion。
  static List<AcapellaRole> assignDefaults(int sourceCount) {
    final n = sourceCount.clamp(1, 4);
    return List<AcapellaRole>.generate(n, (i) {
      return switch (i) {
        0 => AcapellaRole.lead,
        1 => AcapellaRole.response,
        2 => AcapellaRole.pad,
        _ => AcapellaRole.percussion,
      };
    });
  }
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
  double nx;
  double ny;
  bool isPrimary;
  bool muted;

  double get volume {
    final d = math.sqrt(nx * nx + ny * ny).clamp(0.0, 1.414);
    final t = (1.0 - d / 1.414).clamp(0.0, 1.0);
    return 0.12 + t * 0.88;
  }

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
    this.role = AcapellaRole.lead,
    this.type = BeatType.click,
    this.sampleAsset = '',
  });

  final String id;

  /// 触发时间（相对混音时间轴）。
  int timeMs;

  /// 播放哪一段已选声音（0-based，对应画布顺序）。
  int sourceIndex;

  /// 本句/本拍持续时长。
  int playDurationMs;

  /// 起播偏移；阿卡贝拉模式下应落在该源 [HotClip] 内。
  int sliceOffsetMs;

  double strength;
  double volume;
  double pan;
  bool generated;
  bool isDownbeat;

  /// 声部角色。
  AcapellaRole role;

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
    AcapellaRole? role,
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
      role: role ?? this.role,
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
        'role': role.name,
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
      role: AcapellaRole.parse(j['role']?.toString()),
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
    this.rhythmLabel = '',
    this.rhythmHits = const [],
  });

  final String id;
  final String sourceSoundId;
  final double estimatedBpm;
  final int seed;
  final String generatorVersion;
  final List<BeatEvent> events;
  final BeatStyle style;
  final BeatDensity density;

  /// AI/本地随机生成的节拍口诀，如「咚咚打咚咚-」。
  final String rhythmLabel;

  /// 一小节内的强弱序列：1=重击(咚)，0.5≈轻击(打)，0=休止(-)。
  final List<double> rhythmHits;

  static const generatorVersionLocal = 'local_acapella_rhythm_v2';
  static const generatorVersionCodex = 'codex_acapella_rhythm_v1';

  Map<String, dynamic> toJson() => {
        'id': id,
        'mode': 'acapella',
        'sourceSoundId': sourceSoundId,
        'bpm': estimatedBpm,
        'estimatedBpm': estimatedBpm,
        'seed': seed,
        'generatorVersion': generatorVersion,
        'style': style.name,
        'density': density.name,
        'rhythmLabel': rhythmLabel,
        'rhythmHits': rhythmHits,
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
    final rawHits = j['rhythmHits'];
    final hits = <double>[];
    if (rawHits is List) {
      for (final h in rawHits) {
        if (h is num) hits.add(h.toDouble().clamp(0.0, 1.0));
      }
    }
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
      rhythmLabel: j['rhythmLabel']?.toString() ?? '',
      rhythmHits: hits,
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

/// 单段声音中音量最高的有效片段。
///
/// 阿卡贝拉流程：生成编排前先对每段所选录音做 HotClip 截取，
/// 后续所有触发的 [BeatEvent.sliceOffsetMs] 应落在该区间内，
/// 把「最响/最有效」的人声乐句当作声部素材。
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

/// 结构化特征：供本地阿卡贝拉编排或 AI API（不传完整 PCM）。
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
    this.sourceRoles = const [],
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
  final int sourceCount;
  final List<int> sourceDurationsMs;

  /// 各选中声音的最高音量有效片段（画布顺序）。
  final List<HotClip> sourceHotClips;

  /// 各选中声音的声部角色（画布顺序）；空则本地按默认赋。
  final List<AcapellaRole> sourceRoles;

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
        'sourceRoles': sourceRoles.map((e) => e.name).toList(),
        'mode': 'acapella',
        // 请 AI 随机发明节拍型（如「咚咚打咚咚-」），写入 BeatPlan.rhythmHits / rhythmLabel
        'requestRandomRhythm': true,
      };
}
