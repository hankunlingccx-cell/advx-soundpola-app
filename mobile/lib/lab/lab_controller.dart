import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../cloud/cloud_media_client.dart';
import '../data/session.dart';
import '../data/sound_repository.dart';
import '../services/audio_cache_service.dart';
import '../services/auth_service.dart';
import 'beat_analyzer.dart';
import 'beat_generation_api.dart';
import 'beat_models.dart';
import 'lab_mixer.dart';

/// Sound Lab 控制器：用户只需选择音源，其余自动完成。
class LabController extends ChangeNotifier {
  LabController({BeatGenerationApi? api})
      : _api = api ?? BeatGenerationApiGateway.instance {
    mixer.addListener(notifyListeners);
    unawaited(refreshSources());
  }

  final BeatGenerationApi _api;
  final LabMixer mixer = LabMixer();
  final List<LabSoundSource> palette = [];
  final List<LabCanvasNode> canvas = [];

  FeatureSummary? featureSummary;
  BeatPlan? beatPlan;
  bool busy = false;
  bool refreshingSources = false;
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

  /// Sync Collection from cloud when logged in, then build palette from
  /// Drafts + Collection. Missing local files are downloaded via contentId.
  Future<void> refreshSources() async {
    if (refreshingSources) return;
    refreshingSources = true;
    statusMessage = '同步音源…';
    notifyListeners();

    try {
      if (AuthService.instance.isLoggedIn) {
        try {
          final token = await AuthService.instance.requireCloudToken();
          final cloud = CloudMediaClient();
          try {
            final list = await cloud.listContents(token);
            SoundRepository.instance.syncCloudCollection(list.items);
          } finally {
            cloud.close();
          }
        } catch (e) {
          debugPrint('[Lab] cloud sync skipped: $e');
        }
      }

      final token = AuthService.instance.cloudToken;
      final repo = SoundRepository.instance;
      final cache = AudioCacheService.instance;

      // Prefetch local paths for cloud-backed memories (parallel, capped).
      final needFetch = <SoundMemory>[
        ...repo.drafts,
        ...repo.collection,
      ].where((s) {
        final p = s.audioPath;
        final missing = p == null || p.isEmpty || !File(p).existsSync();
        return missing && (s.contentId?.trim().isNotEmpty ?? false);
      }).toList(growable: false);

      if (needFetch.isNotEmpty) {
        statusMessage = '下载云端音频（${needFetch.length}）…';
        notifyListeners();
        const batch = 4;
        for (var i = 0; i < needFetch.length; i += batch) {
          final slice = needFetch.sublist(
            i,
            math.min(i + batch, needFetch.length),
          );
          await Future.wait(
            slice.map((s) => cache.ensureLocalAudio(s, token: token)),
          );
        }
      }

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

      for (final s in repo.drafts) {
        final path = await cache.ensureLocalAudio(s, token: token);
        if (path == null) continue;
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
        final path = await cache.ensureLocalAudio(s, token: token);
        if (path == null) continue;
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

      if (palette.isEmpty) {
        statusMessage = AuthService.instance.isLoggedIn
            ? '暂无可用声音。收藏声片若无本机文件会尝试下载云端音频；请确认已登录且内容为 READY。'
            : '暂无可用声音。登录后可拉取云端收藏，或先去 Record / Drafts。';
      } else {
        statusMessage = '可选 ${palette.length} 段 · 点选 1–4 段生成阿卡贝拉';
      }
    } finally {
      refreshingSources = false;
      notifyListeners();
    }
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
          ? '点选 1–4 段声音，生成阿卡贝拉'
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

  /// 一键：截 HotClip → 阿卡贝拉编排 → 可叠混音试听。
  Future<void> generateAndPlay() async {
    if (canvas.isEmpty) {
      statusMessage = '请先选择声音';
      notifyListeners();
      return;
    }
    if (busy) return;

    busy = true;
    statusMessage = '准备生成阿卡贝拉…';
    notifyListeners();

    try {
      await mixer.stop();
      final primary = primaryNode!;
      final timeline = primary.source.id == 'session_current'
          ? RecordingSession.featureTimeline
          : null;

      statusMessage = '截取各段有效声段（最高音量）…';
      notifyListeners();

      final hotClips = <HotClip>[];
      for (final n in canvas) {
        final tl = n.source.id == 'session_current'
            ? RecordingSession.featureTimeline
            : null;
        final clip = await BeatAnalyzer.findHottestClip(
          durationMs: n.source.durationMs,
          audioPath: n.source.audioPath,
          featuresPath: n.source.featuresPath,
          timeline: tl,
        );
        hotClips.add(clip);
      }

      statusMessage = '分析节拍与声部…';
      notifyListeners();

      final base = await BeatAnalyzer.analyze(
        sourceSoundId: primary.source.id,
        durationMs: primary.source.durationMs,
        audioPath: primary.source.audioPath,
        featuresPath: primary.source.featuresPath,
        timeline: timeline,
        style: BeatStyle.minimal,
        density: BeatDensity.balanced,
      );

      final roles = AcapellaRole.assignDefaults(canvas.length);

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
        sourceHotClips: hotClips,
        sourceRoles: roles,
      );

      statusMessage = '编排阿卡贝拉声部…';
      notifyListeners();

      final contentKey = canvas.map((n) => n.source.id).join('|');
      final seed = Object.hash(
            contentKey,
            primary.source.coverSeed,
            DateTime.now().microsecondsSinceEpoch,
            featureSummary!.onsetsMs.length,
            hotClips.map((c) => c.startMs).join(','),
          ) &
          0x7fffffff;

      beatPlan = await _api.generate(summary: featureSummary!, seed: seed);

      final dur = events.isEmpty
          ? mixDurationMs
          : events
              .map((e) => e.timeMs + e.playDurationMs)
              .reduce(math.max);

      final roleLabels = roles.map((r) => r.label).join(' · ');
      final rhythm = beatPlan?.rhythmLabel;
      statusMessage = rhythm != null && rhythm.isNotEmpty
          ? '节拍 $rhythm · ${featureSummary!.estimatedBpm.toStringAsFixed(0)} BPM · $roleLabels'
          : '阿卡贝拉 · ${featureSummary!.estimatedBpm.toStringAsFixed(0)} BPM · '
              '$roleLabels · ${events.length} 句';
      notifyListeners();

      await mixer.playAcapella(
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
      'title': 'Sound Lab 阿卡贝拉 $stamp',
      'mode': 'acapella',
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
      'note': '自动化声音阿卡贝拉：HotClip 有效声段 + 声部编排；最多 2 层叠唱。',
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
