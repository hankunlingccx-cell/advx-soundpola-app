import 'dart:async';

import 'package:flutter/material.dart';
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
  final _player = AudioPlaybackService.instance;
  String _locationLabel = LocationCaptureService.unsetLabel;
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    final hint = widget.suggestedTitle?.trim();
    _nameCtrl.text =
        (hint != null && hint.isNotEmpty) ? hint : '未命名声音';
    _seed = RecordingSession.visualSeed != 0
        ? RecordingSession.visualSeed
        : DateTime.now().millisecondsSinceEpoch % 10000;
    _player.addListener(_onPlayerChanged);
    _resolveLocation();
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

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
    _player.stop();
    _nameCtrl.dispose();
    _descCtrl.dispose();
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
      final isCloudUploaded = widget.cloudContentId != null;
      final memory = SoundMemory(
        title: name,
        category: _category!,
        description: _descCtrl.text.trim(),
        durationSec: widget.durationSec,
        visualSeed: _seed,
        audioPath: widget.audioPath,
        locationLabel: _locationLabel,
        deviceLabel: widget.fromRing ? 'Ring Sound' : 'Mobile Device',
        status: isCloudUploaded ? SoundStatus.writing : SoundStatus.drafted,
        contentId: widget.cloudContentId,
        cloudState: widget.cloudState,
        visualBakeStatus: VisualBakeStatus.processingVisual,
        rendererVersion: kSoundVisualRendererVersion,
      );

      final timeline = RecordingSession.featureTimeline ??
          AudioFeatureTimeline();
      final paths = await SoundPackageStore.instance.materialize(
        soundId: memory.id,
        sourceAudioPath: widget.audioPath,
        timeline: timeline,
      );

      final packaged = memory.copyWith(
        audioPath: paths.audioPath,
        packageDir: paths.dirPath,
        audioFeaturesPath: paths.featuresPath,
        visualMjpgPath: paths.mjpgPath,
        visualIdxPath: paths.idxPath,
        visualManifestPath: paths.manifestPath,
        coverPath: paths.coverPath,
        visualBakeStatus: VisualBakeStatus.processingVisual,
      );

      SoundRepository.instance.addDraft(packaged);
      RecordingSession.clear();

      // Offline bake — does not block navigation.
      unawaited(VisualBakeService.instance.bakeSound(packaged.id));

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
                  : '可视化帧约 $estMb MB（512² · 12fps · 离线生成）',
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
              onPressed: _saving ? null : widget.onReRecord,
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
