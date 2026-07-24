import 'package:flutter/material.dart';
import '../../data/sound_repository.dart';
import '../../services/audio_playback_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/sound_visual.dart';

const _filters = ['全部', '已暂存', '处理中', '失败'];

class DraftsScreen extends StatefulWidget {
  const DraftsScreen({
    super.key,
    required this.onOpenDetail,
    required this.onPress,
    required this.onStartRecord,
    required this.onLogin,
  });

  final ValueChanged<String> onOpenDetail;
  final ValueChanged<String> onPress;
  final VoidCallback onStartRecord;
  final VoidCallback onLogin;

  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  String _filter = '全部';

  List<SoundMemory> _filtered(List<SoundMemory> items) {
    return switch (_filter) {
      '已暂存' => items.where((s) => s.status == SoundStatus.drafted).toList(),
      '处理中' => items
          .where((s) =>
              s.status == SoundStatus.writing ||
              s.status == SoundStatus.chainPending)
          .toList(),
      '失败' => items
          .where((s) =>
              s.status == SoundStatus.writeFailed ||
              s.status == SoundStatus.chainFailed)
          .toList(),
      _ => items,
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        SoundRepository.instance,
        AuthService.instance,
      ]),
      builder: (context, _) {
        final items = _filtered(SoundRepository.instance.drafts);
        final loggedIn = AuthService.instance.isLoggedIn;
        return ColoredBox(
          color: AppColors.bgPrimary,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: 'Drafts',
                  subtitle: '${SoundRepository.instance.drafts.length} 段暂存',
                ),
                if (!loggedIn) ...[
                  LoginHintCard(onLogin: widget.onLogin),
                  const SizedBox(height: AppSpacing.item),
                ],
                FilterChipRow(
                  options: _filters,
                  selected: _filter,
                  onSelect: (v) => setState(() => _filter = v),
                ),
                const SizedBox(height: AppSpacing.item),
                Expanded(
                  child: items.isEmpty
                      ? _EmptyDrafts(onStartRecord: widget.onStartRecord)
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.pageHorizontal,
                            vertical: AppSpacing.tight,
                          ),
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.tight),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _DraftCard(
                              item: item,
                              onOpen: () => widget.onOpenDetail(item.id),
                              onPress: () => widget.onPress(item.id),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyDrafts extends StatelessWidget {
  const _EmptyDrafts({required this.onStartRecord});
  final VoidCallback onStartRecord;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              height: 120,
              width: 120,
              child: SoundVisualCanvas(seed: 42, active: false),
            ),
            const SizedBox(height: AppSpacing.item),
            const Text(
              '还没有暂存的声音',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              '去捕捉此刻的声音',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.section),
            PrimaryButton(text: '开始捕捉', onPressed: onStartRecord),
          ],
        ),
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.item,
    required this.onOpen,
    required this.onPress,
  });

  final SoundMemory item;
  final VoidCallback onOpen;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final canPress = item.status == SoundStatus.drafted ||
        item.status == SoundStatus.writeFailed ||
        item.status == SoundStatus.chainFailed;

    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                  child: ColoredBox(
                    color: AppColors.surface2,
                    child: SoundVisualCanvas(
                      seed: item.visualSeed,
                      mode: SoundVisualMode.complete,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.tight),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.category} · ${formatDuration(item.durationSec)} · ${item.locationLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        StatusChip(status: item.status),
                      ],
                    ),
                  ),
                  if (canPress)
                    TextButton(
                      onPressed: onPress,
                      child: Text(
                        item.status == SoundStatus.chainFailed
                            ? '重试上链'
                            : 'Press',
                        style: const TextStyle(color: AppColors.accent),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DraftDetailScreen extends StatefulWidget {
  const DraftDetailScreen({
    super.key,
    required this.id,
    required this.onBack,
    required this.onPress,
    required this.onDeleted,
  });

  final String id;
  final VoidCallback onBack;
  final VoidCallback onPress;
  final VoidCallback onDeleted;

  @override
  State<DraftDetailScreen> createState() => _DraftDetailScreenState();
}

class _DraftDetailScreenState extends State<DraftDetailScreen> {
  bool _playing = false;
  bool _editing = false;
  final _player = AudioPlaybackService.instance;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  String? _category;

  @override
  void initState() {
    super.initState();
    final item = SoundRepository.instance.get(widget.id);
    _titleCtrl = TextEditingController(text: item?.title ?? '');
    _descCtrl = TextEditingController(text: item?.description ?? '');
    _category = item?.category;
  }

  @override
  void dispose() {
    _player.stop();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(String? path) async {
    if (path == null || path.isEmpty) {
      setState(() => _playing = !_playing);
      return;
    }
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
    } else {
      await _player.play(path);
      setState(() => _playing = true);
    }
  }

  void _saveEdit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称与分类不能为空')),
      );
      return;
    }
    SoundRepository.instance.update(
      widget.id,
      (s) => s.copyWith(
        title: title,
        category: _category,
        description: _descCtrl.text.trim(),
      ),
    );
    setState(() => _editing = false);
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这段声音？'),
        content: const Text('录音、声音视觉和相关记忆信息将被永久移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (SoundRepository.instance.delete(widget.id)) {
        widget.onDeleted();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NFC 已写入的声音不可删除，请重试上链')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SoundRepository.instance,
      builder: (context, _) {
        final item = SoundRepository.instance.get(widget.id);
        if (item == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Drafts')),
            body: const Center(child: Text('声音不存在')),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          appBar: AppBar(
            title: const Text('暂存详情'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: widget.onBack,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (_editing) {
                    _saveEdit();
                  } else {
                    setState(() => _editing = true);
                  }
                },
                child: Text(
                  _editing ? '保存' : '编辑',
                  style: const TextStyle(color: AppColors.accent),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageHorizontal,
              ),
              children: [
                GestureDetector(
                  onTap: () => _togglePlay(item.audioPath),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(AppRadii.collectionCard),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ColoredBox(
                        color: AppColors.surface1,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SoundVisualCanvas(
                              seed: item.visualSeed,
                              mode: _playing
                                  ? SoundVisualMode.playback
                                  : SoundVisualMode.complete,
                            ),
                            Icon(
                              _playing
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                              size: 44,
                              color: AppColors.accent.withValues(alpha: 0.85),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.item),
                if (_editing) ...[
                  SpTextField(
                    controller: _titleCtrl,
                    label: '声音名称',
                    maxLength: 20,
                  ),
                  const SizedBox(height: AppSpacing.item),
                  const SectionLabel('分类'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: soundCategories.map((c) {
                      final active = c == _category;
                      return GestureDetector(
                        onTap: () => setState(() => _category = c),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.accent.withValues(alpha: 0.15)
                                : AppColors.surface1,
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(
                              color: active
                                  ? AppColors.accent
                                  : AppColors.border,
                            ),
                          ),
                          child: Text(
                            c,
                            style: TextStyle(
                              color: active
                                  ? AppColors.accent
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.item),
                  SpTextField(
                    controller: _descCtrl,
                    label: '描述（选填）',
                    maxLines: 3,
                    maxLength: 200,
                  ),
                ] else ...[
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '#${item.category} · ${formatDuration(item.durationSec)}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  StatusChip(status: item.status),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.item),
                    Text(
                      item.description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.item),
                  MetaRow(
                    label: '录制时间',
                    value: formatRecordedAt(item.recordedAt),
                  ),
                  MetaRow(label: '地点', value: item.locationLabel),
                  MetaRow(
                    label: '时长',
                    value: formatDuration(item.durationSec),
                  ),
                  MetaRow(label: '设备', value: item.deviceLabel),
                ],
                const SizedBox(height: AppSpacing.block),
                PrimaryButton(
                  text: item.status == SoundStatus.chainFailed
                      ? '重试上链'
                      : '写入声片',
                  onPressed: widget.onPress,
                ),
                const SizedBox(height: AppSpacing.tight),
                SecondaryButton(
                  text: '删除声音',
                  danger: true,
                  onPressed: _confirmDelete,
                ),
                const SizedBox(height: AppSpacing.section),
              ],
            ),
          ),
        );
      },
    );
  }
}
