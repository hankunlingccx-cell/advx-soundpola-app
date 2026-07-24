import 'package:flutter/material.dart';
import '../../data/session.dart';
import '../../data/sound_repository.dart';
import '../../services/audio_playback_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/sound_visual.dart';

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
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: soundCategories
              .map(
                (c) => ListTile(
                  title: Text(c),
                  onTap: () => Navigator.pop(ctx, c),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (picked != null) setState(() => _category = picked);
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请完成命名')));
      return;
    }
    if (_category == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择分类')));
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
      ),
    );
    RecordingSession.clear();
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: AppColors.canvasBg,
      appBar: AppBar(
        backgroundColor: AppColors.canvasBg,
        elevation: 0,
        foregroundColor: AppColors.ink950,
        title: const Text('录音结果'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
          children: [
            SizedBox(
              height: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.card),
                child: Material(
                  color: AppColors.primary50,
                  child: InkWell(
                    onTap: _togglePlay,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.item),
                          child: SoundVisualCanvas(seed: _seed, active: _playing),
                        ),
                        Icon(
                          _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                          size: 56,
                          color: AppColors.primary700.withValues(alpha: 0.85),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.item),
            Text(
              '${formatRecordedAt(now)}  ·  ${formatDuration(widget.durationSec)}',
              style: const TextStyle(color: AppColors.ink400, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.section),
            const SectionLabel('声音名称'),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.input),
                  borderSide: const BorderSide(color: AppColors.line200),
                ),
              ),
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
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(AppRadii.input),
                  border: Border.all(color: AppColors.line200),
                ),
                child: Text(
                  _category ?? '选择分类',
                  style: TextStyle(
                    color: _category == null ? AppColors.ink400 : AppColors.ink950,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.item),
            const SectionLabel('描述（选填）'),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '记录这段声音背后的故事……',
                hintStyle: const TextStyle(color: AppColors.ink400),
                filled: true,
                fillColor: AppColors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.input),
                  borderSide: const BorderSide(color: AppColors.line200),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.block),
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
