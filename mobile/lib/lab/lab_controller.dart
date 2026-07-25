import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/session.dart';
import '../data/sound_repository.dart';
import 'beat_analyzer.dart';
import 'beat_generation_api.dart';
import 'beat_models.dart';
import 'lab_mixer.dart';

/// Sound Lab 控制器：用户只需选择音源，其余自动完成。
class LabController extends ChangeNotifier {
  LabController({BeatGenerationApi? api})
      : _api = api ?? BeatGenerationApiGateway.instance {
    mixer.addListener(notifyListeners);
    refreshSources();
  }

  final BeatGenerationApi _api;
  final LabMixer mixer = LabMixer();
  final List<LabSoundSource> palette = [];
  final List<LabCanvasNode> canvas = [];

  FeatureSummary? featureSummary;
  BeatPlan? beatPlan;
  bool busy = false;
  String? statusMessage;

  static const maxCanvasNodes = 4;

  /// 自动布局：绕监听核心均匀摆放。
  static const _slots = <(double, double)>[
    (0.0, -0.55),
    (0.55, 0.15),
    (-0.55, 0.15),
    (0.0, 0.55),
  ];

  List<BeatEvent> get events => beatPlan?.events ?? const [];

  bool get canPlay => canvas.isNotEmpty;

  int get mixDurationMs {
    if (canvas.isEmpty) return featureSummary?.durationMs ?? 0;
    var maxMs = 0;
    for (final n in canvas) {
      if (n.source.durationMs > maxMs) maxMs = n.source.durationMs;
    }
    if (featureSummary != null && featureSummary!.durationMs > maxMs) {
      maxMs = featureSummary!.durationMs;
    }
    if (events.isNotEmpty) {
      final last = events.map((e) => e.timeMs).reduce(math.max);
      if (last + 500 > maxMs) maxMs = last + 500;
    }
    return maxMs;
  }

  LabCanvasNode? get primaryNode {
    for (final n in canvas) {
      if (n.isPrimary) return n;
    }
    return canvas.isEmpty ? null : canvas.first;
  }

  bool isSelected(LabSoundSource source) =>
      canvas.any((n) => n.source.id == source.id);

  void refreshSources() {
    palette.clear();
    final sessionPath = RecordingSession.audioPath;
    if (sessionPath != null &&
        sessionPath.isNotEmpty &&
        File(sessionPath).existsSync()) {
      palette.add(
        LabSoundSource(
          id: 'session_current',
          kind: LabSourceKind.session,
          title: RecordingSession.suggestedTitle?.trim().isNotEmpty == true
              ? RecordingSession.suggestedTitle!
              : '当前录音',
          audioPath: sessionPath,
          durationMs: RecordingSession.durationSec * 1000,
          coverSeed: RecordingSession.visualSeed,
        ),
      );
    }

    final repo = SoundRepository.instance;
    for (final s in repo.drafts) {
      final path = s.audioPath;
      if (path == null || path.isEmpty || !File(path).existsSync()) continue;
      palette.add(
        LabSoundSource(
          id: 'draft_${s.id}',
          kind: LabSourceKind.draft,
          title: s.title,
          audioPath: path,
          durationMs: s.durationSec * 1000,
          coverSeed: s.visualSeed,
          featuresPath: s.audioFeaturesPath,
          coverPath: s.coverPath,
          memoryId: s.id,
        ),
      );
    }
    for (final s in repo.collection) {
      final path = s.audioPath;
      if (path == null || path.isEmpty || !File(path).existsSync()) continue;
      palette.add(
        LabSoundSource(
          id: 'col_${s.id}',
          kind: LabSourceKind.collection,
          title: s.title,
          audioPath: path,
          durationMs: s.durationSec * 1000,
          coverSeed: s.visualSeed,
          featuresPath: s.audioFeaturesPath,
          coverPath: s.coverPath,
          memoryId: s.id,
        ),
      );
    }
    notifyListeners();
  }

  /// 点选 / 取消点选；自动摆位，无需拖拽编辑。
  Future<void> toggleSelect(LabSoundSource source) async {
    if (isSelected(source)) {
      canvas.removeWhere((n) => n.source.id == source.id);
      await mixer.removeSource(source.id);
      _rebalanceSlots();
      if (canvas.isNotEmpty && !canvas.any((n) => n.isPrimary)) {
        canvas.first.isPrimary = true;
      }
      beatPlan = null;
      featureSummary = null;
      statusMessage = canvas.isEmpty
          ? '点选 1–4 段声音即可'
          : '已选择 ${canvas.length} 段';
      notifyListeners();
      return;
    }

    if (canvas.length >= maxCanvasNodes) {
      statusMessage = '最多选择 4 段声音';
      notifyListeners();
      return;
    }

    final slot = _slots[canvas.length];
    final node = LabCanvasNode(
      source: source,
      nx: slot.$1,
      ny: slot.$2,
      isPrimary: canvas.isEmpty,
    );
    canvas.add(node);
    await mixer.ensureSource(node);
    await mixer.applySpatial(node);
    beatPlan = null;
    featureSummary = null;
    statusMessage = '已选择 ${canvas.length} 段 · 主声音：${primaryNode?.source.title}';
    notifyListeners();
  }

  void _rebalanceSlots() {
    for (var i = 0; i < canvas.length; i++) {
      final slot = _slots[i];
      canvas[i].nx = slot.$1;
      canvas[i].ny = slot.$2;
      mixer.applySpatial(canvas[i]);
    }
  }

  /// 一键：分析主声音 BPM → 生成轮播节拍计划 → 按拍轮播试听。
  Future<void> generateAndPlay() async {
    if (canvas.isEmpty) {
      statusMessage = '请先选择声音';
      notifyListeners();
      return;
    }
    if (busy) return;

    busy = true;
    statusMessage = '分析节拍…';
    notifyListeners();

    try {
      await mixer.stop();
      final primary = primaryNode!;
      final timeline = primary.source.id == 'session_current'
          ? RecordingSession.featureTimeline
          : null;

      final base = await BeatAnalyzer.analyze(
        sourceSoundId: primary.source.id,
        durationMs: primary.source.durationMs,
        audioPath: primary.source.audioPath,
        featuresPath: primary.source.featuresPath,
        timeline: timeline,
        style: BeatStyle.minimal,
        density: BeatDensity.balanced,
      );

      featureSummary = FeatureSummary(
        durationMs: base.durationMs,
        estimatedBpm: base.estimatedBpm,
        onsetsMs: base.onsetsMs,
        energySegments: base.energySegments,
        silenceRanges: base.silenceRanges,
        requestedStyle: base.requestedStyle,
        requestedDensity: base.requestedDensity,
        beatGridMs: base.beatGridMs,
        candidateBeatMs: base.candidateBeatMs,
        sourceSoundId: base.sourceSoundId,
        sourceCount: canvas.length,
        sourceDurationsMs:
            canvas.map((n) => n.source.durationMs).toList(growable: false),
      );

      statusMessage = '生成轮播计划…';
      notifyListeners();

      final seed = primary.source.coverSeed == 0
          ? primary.source.id.hashCode & 0x7fffffff
          : primary.source.coverSeed;

      beatPlan = await _api.generate(summary: featureSummary!, seed: seed);

      final dur = events.isEmpty
          ? mixDurationMs
          : events.last.timeMs + events.last.playDurationMs;

      statusMessage =
          '按 ${featureSummary!.estimatedBpm.toStringAsFixed(0)} BPM 轮播 ${canvas.length} 段 · ${events.length} 拍';
      notifyListeners();

      await mixer.playRotate(
        nodes: canvas,
        beats: events,
        durationMs: dur,
        startMs: 0,
      );
    } catch (e) {
      statusMessage = '失败：$e';
      notifyListeners();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> stopMix() => mixer.stop();

  Future<File> exportWork() async {
    if (canvas.isEmpty) throw StateError('尚未选择声音');
    if (beatPlan == null) {
      busy = true;
      statusMessage = '生成后导出…';
      notifyListeners();
      try {
        await generateAndPlay();
        await mixer.stop();
      } finally {
        busy = false;
        notifyListeners();
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final folder = Directory('${dir.path}/lab_exports/work_$stamp');
    await folder.create(recursive: true);

    final session = {
      'title': 'Sound Lab 轮播 $stamp',
      'mode': 'beat_rotate',
      'createdAt': DateTime.now().toIso8601String(),
      'sources': canvas
          .map((n) => {
                'id': n.source.id,
                'title': n.source.title,
                'kind': n.source.kind.name,
                'durationMs': n.source.durationMs,
                'nx': n.nx,
                'ny': n.ny,
                'isPrimary': n.isPrimary,
              })
          .toList(),
      'featureSummary': featureSummary?.toJson(),
      'beatPlan': beatPlan?.toJson(),
      'note': '按节拍规律轮播所选音频；不叠加鼓点素材。',
    };
    final jsonFile = File('${folder.path}/session.json');
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(session),
      flush: true,
    );

    statusMessage = '已导出至 ${folder.path}';
    notifyListeners();
    return jsonFile;
  }

  @override
  void dispose() {
    mixer.removeListener(notifyListeners);
    mixer.dispose();
    super.dispose();
  }
}
