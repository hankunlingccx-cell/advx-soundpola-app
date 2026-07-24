import 'package:flutter/material.dart';
import '../../data/sound_repository.dart';
import '../../services/audio_playback_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/sound_visual.dart';

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key, required this.onOpenMemory});

  final ValueChanged<String> onOpenMemory;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SoundRepository.instance,
      builder: (context, _) {
        final items = SoundRepository.instance.collection;
        return ColoredBox(
          color: AppColors.canvasBg,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: 'Collection',
                  subtitle: '${items.length} 段收藏',
                ),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('还没有收藏的声音', style: TextStyle(color: AppColors.ink600)))
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.pageHorizontal,
                          ),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: AppSpacing.tight,
                            mainAxisSpacing: AppSpacing.tight,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _CollectionCard(
                              item: item,
                              onTap: () => onOpenMemory(item.id),
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

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.item, required this.onTap});
  final SoundMemory item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppRadii.collectionCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: AppColors.primary50,
                child: SoundVisualCanvas(seed: item.visualSeed, active: false),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.tight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink950),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatRecordedAt(item.recordedAt).substring(0, 10),
                    style: const TextStyle(color: AppColors.ink400, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, required this.id, required this.onBack});

  final String id;
  final VoidCallback onBack;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  bool _playing = false;
  bool _assetExpanded = false;
  final _player = AudioPlaybackService.instance;

  @override
  void dispose() {
    _player.stop();
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SoundRepository.instance,
      builder: (context, _) {
        final item = SoundRepository.instance.get(widget.id);
        if (item == null) {
          return Scaffold(
            body: Center(
              child: TextButton(onPressed: widget.onBack, child: const Text('返回')),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.canvasBg,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: widget.onBack,
                        child: const Text('返回', style: TextStyle(color: AppColors.ink600)),
                      ),
                      const Text('Memory', style: TextStyle(fontWeight: FontWeight.w600)),
                      const Text('分享', style: TextStyle(color: AppColors.primary700, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.tight),
                  Text(formatRecordedAt(item.recordedAt), style: const TextStyle(color: AppColors.ink400, fontSize: 12)),
                  Text(item.locationLabel, style: const TextStyle(color: AppColors.ink600, fontSize: 13)),
                  const SizedBox(height: AppSpacing.item),
                  GestureDetector(
                    onTap: () => _togglePlay(item.audioPath),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.collectionCard),
                      child: SizedBox(
                        height: 340,
                        child: ColoredBox(
                          color: AppColors.primary50,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.section),
                            child: SoundVisualCanvas(seed: item.visualSeed, active: _playing),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  Text(
                    item.title,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.ink950),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '#${item.category}  ·  ${formatDuration(item.durationSec)}',
                    style: const TextStyle(color: AppColors.ink600),
                  ),
                  const SizedBox(height: 8),
                  StatusChip(status: item.status),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.item),
                    Text(item.description, style: const TextStyle(color: AppColors.ink600, height: 1.5)),
                  ],
                  const SizedBox(height: AppSpacing.section),
                  InkWell(
                    onTap: () => setState(() => _assetExpanded = !_assetExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.tight),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('声片与数字资产', style: TextStyle(fontWeight: FontWeight.w500)),
                          Text(
                            _assetExpanded ? '收起' : '展开',
                            style: const TextStyle(color: AppColors.primary700, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_assetExpanded) ...[
                    MetaRow(label: '声片编号', value: item.discId ?? '—'),
                    MetaRow(label: '数字资产', value: item.assetId ?? '—'),
                    MetaRow(label: '录制设备', value: item.deviceLabel),
                    const MetaRow(label: '绑定状态', value: '永久绑定'),
                  ],
                  const Spacer(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
