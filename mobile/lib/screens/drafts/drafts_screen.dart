import 'package:flutter/material.dart';
import '../../data/sound_repository.dart';
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
  });

  final ValueChanged<String> onOpenDetail;
  final ValueChanged<String> onPress;
  final VoidCallback onStartRecord;

  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  String _filter = '全部';

  List<SoundMemory> _filtered(List<SoundMemory> items) {
    return switch (_filter) {
      '已暂存' => items.where((s) => s.status == SoundStatus.drafted).toList(),
      '处理中' => items
          .where((s) => s.status == SoundStatus.writing || s.status == SoundStatus.chainPending)
          .toList(),
      '失败' => items
          .where((s) =>
              s.status == SoundStatus.writeFailed || s.status == SoundStatus.chainFailed)
          .toList(),
      _ => items,
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SoundRepository.instance,
      builder: (context, _) {
        final items = _filtered(SoundRepository.instance.drafts);
        return ColoredBox(
          color: AppColors.canvasBg,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: 'Drafts',
                  subtitle: '${SoundRepository.instance.drafts.length} 段暂存',
                ),
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
                          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.tight),
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
            SizedBox(
              height: 120,
              width: 120,
              child: SoundVisualCanvas(seed: 42, active: false),
            ),
            const SizedBox(height: AppSpacing.item),
            const Text('还没有暂存的声音', style: TextStyle(color: AppColors.ink950, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('去捕捉此刻的声音', style: TextStyle(color: AppColors.ink600)),
            const SizedBox(height: AppSpacing.section),
            PrimaryButton(text: '开始录音', onPressed: onStartRecord),
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
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.tight),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.chip),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: ColoredBox(
                    color: AppColors.primary50,
                    child: SoundVisualCanvas(seed: item.visualSeed, active: false),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.tight),
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
                        color: AppColors.ink950,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.category} · ${formatDuration(item.durationSec)}',
                      style: const TextStyle(color: AppColors.ink600, fontSize: 13),
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
                    item.status == SoundStatus.chainFailed ? '重试上链' : 'Press',
                    style: const TextStyle(color: AppColors.primary700),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class DraftDetailScreen extends StatelessWidget {
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

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这段声音？'),
        content: const Text('录音、声音视觉和相关记忆信息将被永久移除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (SoundRepository.instance.delete(id)) {
        onDeleted();
      } else if (context.mounted) {
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
        final item = SoundRepository.instance.get(id);
        if (item == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Drafts')),
            body: const Center(child: Text('声音不存在')),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.canvasBg,
          appBar: AppBar(
            backgroundColor: AppColors.canvasBg,
            elevation: 0,
            foregroundColor: AppColors.ink600,
            title: const Text('暂存详情', style: TextStyle(color: AppColors.ink950)),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.collectionCard),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ColoredBox(
                        color: AppColors.primary50,
                        child: SoundVisualCanvas(seed: item.visualSeed, active: true),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.item),
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink950,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '#${item.category} · ${formatDuration(item.durationSec)}',
                    style: const TextStyle(color: AppColors.ink600),
                  ),
                  const SizedBox(height: 8),
                  StatusChip(status: item.status),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.item),
                    Text(item.description, style: const TextStyle(color: AppColors.ink600, height: 1.5)),
                  ],
                  const SizedBox(height: AppSpacing.item),
                  Text(formatRecordedAt(item.recordedAt), style: const TextStyle(color: AppColors.ink400, fontSize: 13)),
                  Text(item.locationLabel, style: const TextStyle(color: AppColors.ink600, fontSize: 13)),
                  const Spacer(),
                  PrimaryButton(
                    text: item.status == SoundStatus.chainFailed ? '重试上链' : '写入声片',
                    onPressed: onPress,
                  ),
                  const SizedBox(height: AppSpacing.tight),
                  SecondaryButton(
                    text: '删除声音',
                    onPressed: () => _confirmDelete(context),
                  ),
                  const SizedBox(height: AppSpacing.section),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
