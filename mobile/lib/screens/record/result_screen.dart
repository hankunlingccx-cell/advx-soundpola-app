import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../cloud/cloud_prefetch.dart';
import '../../data/session.dart';
import '../../data/sound_repository.dart';
import '../../services/audio_playback_service.dart';
import '../../services/location_capture_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../visual/audio_feature_timeline.dart';
import '../../visual/sound_package_store.dart';
import '../../visual/visual_bake_service.dart';
import '../../widgets/design_components.dart';
import '../../widgets/sound_visual.dart';
import '../../widgets/sp_category_picker.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.durationSec,
    required this.audioPath,
    required this.onSaved,
    required this.onReRecord,
    this.fromImport = false,
    this.fromRing = false,
    this.suggestedTitle,
    this.cloudContentId,
    this.cloudState,
    this.cloudUploadError,
  });

  final int durationSec;
  final String audioPath;
  final VoidCallback onSaved;
  final VoidCallback onReRecord;
  final bool fromImport;
  final bool fromRing;
  final String? suggestedTitle;
  final String? cloudContentId;
  final String? cloudState;
  final String? cloudUploadError;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _category;
  late final int _seed;
  bool _playing = false;
  bool _saving = false;
  bool _committed = false;
  bool _preparing = true;
  String? _prepareError;
  String? _pendingId;
  final _player = AudioPlaybackService.instance;
  String _locationLabel = LocationCaptureService.unsetLabel;
  bool _locating = true;
  static final _rng = Random();

  @override
  void initState() {
    super.initState();
    final hint = widget.suggestedTitle?.trim();
    _nameCtrl.text =
        (hint != null && hint.isNotEmpty) ? hint : '未命名声音';
    _seed = RecordingSession.visualSeed != 0
        ? RecordingSession.visualSeed
        : SoundMemory.stableVisualSeed(
            soundId: RecordingSession.pendingSoundId,
          );
    _player.addListener(_onPlayerChanged);
    _resolveLocation();
    unawaited(_prepareVisualPackage());
  }

  void _onPlayerChanged() {
    final playing =
        _player.isPlaying && _player.currentPath == widget.audioPath;
    if (playing != _playing && mounted) {
      setState(() => _playing = playing);
    }
  }

  Future<void> _resolveLocation() async {
    final label = await LocationCaptureService.capturePlaceLabel();
    if (!mounted) return;
    setState(() {
      _locationLabel = label;
      _locating = false;
    });
  }

  String _newSoundId() =>
      DateTime.now().microsecondsSinceEpoch.toString() +
      _rng.nextInt(9999).toString().padLeft(4, '0');

  /// Materialize package + kick Indexed-MJPEG bake as soon as result opens.
  Future<void> _prepareVisualPackage() async {
    try {
      // Reuse in-progress prepare if session already allocated an id (rare).
      var soundId = RecordingSession.pendingSoundId;
      if (soundId == null ||
          RecordingSession.pendingPackageDir == null ||
          RecordingSession.pendingFeaturesPath == null) {
        soundId = _newSoundId();
        final timeline =
            RecordingSession.featureTimeline ?? AudioFeatureTimeline();
        final paths = await SoundPackageStore.instance.materialize(
          soundId: soundId,
          sourceAudioPath: widget.audioPath,
          timeline: timeline,
          moveAudio: false,
        );
        RecordingSession.setPendingPackage(
          soundId: soundId,
          dirPath: paths.dirPath,
          audioPath: paths.audioPath,
          featuresPath: paths.featuresPath,
          mjpgPath: paths.mjpgPath,
          idxPath: paths.idxPath,
          manifestPath: paths.manifestPath,
          coverPath: paths.coverPath,
          mp4Path: paths.mp4Path,
        );
      }

      unawaited(
        VisualBakeService.instance.bakeSound(
          soundId,
          visualSeed: _seed,
          durationSec: widget.durationSec,
        ),
      );

      if (!mounted) return;
      setState(() {
        _pendingId = soundId;
        _preparing = false;
        _prepareError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _prepareError = e.toString();
      });
    }
  }

  Future<VisualBakeStatus> _resolveBakeStatus(String soundId) async {
    final err = RecordingSession.pendingBakeError;
    if (err != null && err.isNotEmpty) return VisualBakeStatus.failed;

    final mjpg = RecordingSession.pendingMjpgPath;
    final idx = RecordingSession.pendingIdxPath;
    final manifest = RecordingSession.pendingManifestPath;
    if (mjpg != null &&
        idx != null &&
        manifest != null &&
        await File(mjpg).exists() &&
        await File(idx).exists() &&
        await File(manifest).exists()) {
      return VisualBakeStatus.ready;
    }
    if (VisualBakeService.instance.isBusy) {
      return VisualBakeStatus.processingVisual;
    }
    return VisualBakeStatus.processingVisual;
  }

  Future<void> _discardPendingPackage() async {
    final id = _pendingId ?? RecordingSession.pendingSoundId;
    if (id == null) return;
    await SoundPackageStore.instance.deletePackage(id);
    RecordingSession.clearPendingPackage();
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
    _player.stop();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    if (!_committed) {
      unawaited(_discardPendingPackage());
    }
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
    } else {
      await _player.play(widget.audioPath);
      setState(() => _playing = true);
    }
  }

  Future<void> _pickCategory() async {
    final picked = await SpCategoryPicker.show(
      context,
      current: _category,
    );
    if (picked != null) setState(() => _category = picked);
  }

  Future<void> _onReRecordPressed() async {
    if (_saving) return;
    await _player.stop();
    await _discardPendingPackage();
    _committed = true; // avoid double-delete in dispose
    widget.onReRecord();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请完成命名')),
      );
      return;
    }
    if (_category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择分类')),
      );
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);

    try {
      // Ensure package exists even if early prepare failed.
      if (_pendingId == null || RecordingSession.pendingPackageDir == null) {
        await _prepareVisualPackage();
        if (_pendingId == null || RecordingSession.pendingPackageDir == null) {
          throw StateError(_prepareError ?? '可视化包准备失败');
        }
      }

      final soundId = _pendingId!;
      final packagedAudio = RecordingSession.pendingAudioPath!;
      final bakeStatus = await _resolveBakeStatus(soundId);
      final isCloudUploaded = widget.cloudContentId != null;

      final packaged = SoundMemory(
        id: soundId,
        title: name,
        category: _category!,
        description: _descCtrl.text.trim(),
        durationSec: widget.durationSec,
        visualSeed: _seed,
        audioPath: packagedAudio,
        locationLabel: _locationLabel,
        deviceLabel: widget.fromRing ? 'Ring Sound' : 'Mobile Device',
        status: isCloudUploaded ? SoundStatus.writing : SoundStatus.drafted,
        contentId: widget.cloudContentId,
        cloudState: widget.cloudState,
        packageDir: RecordingSession.pendingPackageDir,
        audioFeaturesPath: RecordingSession.pendingFeaturesPath,
        visualMjpgPath: RecordingSession.pendingMjpgPath,
        visualIdxPath: RecordingSession.pendingIdxPath,
        visualManifestPath: RecordingSession.pendingManifestPath,
        coverPath: RecordingSession.pendingCoverPath,
        visualMp4Path: RecordingSession.pendingMp4Path,
        visualBakeStatus: bakeStatus,
        visualBakeError: bakeStatus == VisualBakeStatus.failed
            ? RecordingSession.pendingBakeError
            : null,
        rendererVersion: kSoundVisualRendererVersion,
      );

      SoundRepository.instance.addDraft(packaged);

      // Drop the original recordings/ copy once package is committed.
      final src = File(widget.audioPath);
      if (src.path != packagedAudio && await src.exists()) {
        try {
          await src.delete();
        } catch (_) {}
      }

      // If bake finished before draft existed, patch ready paths onto repo.
      if (bakeStatus == VisualBakeStatus.ready) {
        SoundRepository.instance.update(
          soundId,
          (s) => s.copyWith(
            visualBakeStatus: VisualBakeStatus.ready,
            clearVisualBakeError: true,
          ),
        );
        CloudPrefetchService.instance.schedule(soundId);
      } else if (bakeStatus == VisualBakeStatus.failed) {
        CloudPrefetchService.instance.schedule(soundId);
      } else if (bakeStatus != VisualBakeStatus.failed &&
          !VisualBakeService.instance.isBusy) {
        // Resume bake if early kick never ran / finished busy race.
        unawaited(
          VisualBakeService.instance.bakeSound(
            soundId,
            visualSeed: _seed,
            durationSec: widget.durationSec,
          ),
        );
      }

      _committed = true;
      RecordingSession.clear();

      if (!mounted) return;
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final estBytes = SoundPackageStore.estimateVisualBytes(
      durationSec: widget.durationSec,
    );
    final estMb = (estBytes / (1024 * 1024)).toStringAsFixed(1);
    final bakeHint = _prepareError != null
        ? '可视化准备失败，保存时将重试'
        : (_preparing
            ? '正在准备可视化帧序列…'
            : '可视化帧约 $estMb MB（512² · 12fps · 录音后已开始生成）');
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: Text(
          widget.fromRing
              ? '指环录音完成'
              : (widget.fromImport ? '导入结果' : '录音结果'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal,
          ),
          children: [
            SizedBox(
              height: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.card),
                child: Material(
                  color: AppColors.surface1,
                  child: InkWell(
                    onTap: _togglePlay,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.item),
                          child: SoundVisualCanvas(
                            seed: _seed,
                            mode: _playing
                                ? SoundVisualMode.playback
                                : SoundVisualMode.complete,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _playing ? '暂停' : '试听',
                            style: TextStyle(
                              color: AppColors.accent.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.item),
            Text(
              '${formatRecordedAt(now)}  ·  ${formatDuration(widget.durationSec)} · '
              '${_locating ? '定位中…' : _locationLabel}',
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              widget.fromRing
                  ? '来自指环 · 已保存到本机并可试听'
                  : bakeHint,
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.section),
            SpTextField(
              controller: _nameCtrl,
              label: '声音名称',
              maxLength: 20,
            ),
            const SizedBox(height: AppSpacing.item),
            const SectionLabel('分类'),
            GestureDetector(
              onTap: _pickCategory,
              child: Container(
                height: AppSizes.inputHeight,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(AppRadii.input),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  _category ?? '选择分类',
                  style: TextStyle(
                    color: _category == null
                        ? AppColors.textTertiary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.item),
            SpTextField(
              controller: _descCtrl,
              label: '描述（可选）',
              maxLength: 80,
              maxLines: 3,
            ),
            const SizedBox(height: AppSpacing.section),
            PrimaryButton(
              text: _saving ? '正在保存…' : '保存至 Drafts',
              onPressed: _save,
              enabled: !_saving,
            ),
            const SizedBox(height: AppSpacing.item),
            TextButton(
              onPressed: _saving ? null : _onReRecordPressed,
              child: Text(
                widget.fromRing
                    ? '完成'
                    : (widget.fromImport ? '重新选择' : '重新录音'),
                style: const TextStyle(color: AppColors.accent),
              ),
            ),
            const SizedBox(height: AppSpacing.block),
          ],
        ),
      ),
    );
  }
}
