import 'package:flutter/material.dart';
import '../../data/session.dart';
import '../../data/sound_repository.dart';
import '../../services/audio_playback_service.dart';
import '../../services/location_capture_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
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
  });

  final int durationSec;
  final String audioPath;
  final VoidCallback onSaved;
  final VoidCallback onReRecord;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _nameCtrl = TextEditingController(text: '未命名声音');
  final _descCtrl = TextEditingController();
  String? _category;
  final _seed = DateTime.now().millisecondsSinceEpoch % 10000;
  bool _playing = false;
  final _player = AudioPlaybackService.instance;
  String _locationLabel = LocationCaptureService.unsetLabel;
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    _resolveLocation();
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

  void _save() {
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
    SoundRepository.instance.addDraft(
      SoundMemory(
        title: name,
        category: _category!,
        description: _descCtrl.text.trim(),
        durationSec: widget.durationSec,
        visualSeed: _seed,
        audioPath: widget.audioPath,
        locationLabel: _locationLabel,
      ),
    );
    RecordingSession.clear();
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(title: const Text('录音结果')),
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
              label: '描述（选填）',
              hint: '记录这段声音背后的故事……',
              maxLines: 3,
              maxLength: 200,
            ),
            const SizedBox(height: AppSpacing.block),
            const MetaRow(label: '声片稀有度', value: '待揭晓'),
            const SizedBox(height: 6),
            const Text(
              '稀有度由实体声片决定，写入声片时揭晓',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.item),
            SecondaryButton(text: '重新录制', onPressed: widget.onReRecord),
            const SizedBox(height: AppSpacing.tight),
            PrimaryButton(text: '保存至 Drafts', onPressed: _save),
            const SizedBox(height: AppSpacing.section),
          ],
        ),
      ),
    );
  }
}
