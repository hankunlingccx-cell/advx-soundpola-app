import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../lab/beat_models.dart';
import '../../lab/lab_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';
import '../../widgets/sound_visual.dart';

/// 用户只需点选声音，一键生成并试听；无需手动编辑节拍 / 拖拽摆位。
class SoundLabScreen extends StatefulWidget {
  const SoundLabScreen({super.key, this.embeddedInShell = false});

  /// 作为底部导航第四 Tab 嵌入时为 true（无返回键，右上角进 Account）。
  final bool embeddedInShell;

  @override
  State<SoundLabScreen> createState() => _SoundLabScreenState();
}

class _SoundLabScreenState extends State<SoundLabScreen> {
  late final LabController _c;

  @override
  void initState() {
    super.initState();
    _c = LabController();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _snack(String msg) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final playing = _c.mixer.isPlaying;
        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          appBar: AppBar(
            title: const Text('Sound Lab'),
            automaticallyImplyLeading: !widget.embeddedInShell,
            leading: widget.embeddedInShell
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                  ),
            actions: [
              IconButton(
                tooltip: '刷新音源',
                onPressed: _c.refreshSources,
                icon: const Icon(Icons.refresh),
              ),
              if (widget.embeddedInShell) ...[
                const SizedBox(width: 4),
                const AccountAvatarButton(compact: true),
                const SizedBox(width: 8),
              ],
            ],
          ),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(
                    '点选 1–4 段声音 → 截取有效声段 → 程序随机发明节拍并编排阿卡贝拉。',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
                if (_c.statusMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      _c.statusMessage!,
                      style: const TextStyle(
                        color: AppColors.accentSoft,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Expanded(
                  child: _c.palette.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无可用声音\n请先在 Record 录音或打开 Drafts / Collection',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              height: 1.5,
                            ),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.82,
                          ),
                          itemCount: _c.palette.length,
                          itemBuilder: (context, i) {
                            final s = _c.palette[i];
                            final selected = _c.isSelected(s);
                            final isPrimary =
                                selected && _c.primaryNode?.source.id == s.id;
                            return _SelectTile(
                              source: s,
                              selected: selected,
                              isPrimary: isPrimary,
                              onTap: () => _c.toggleSelect(s),
                            );
                          },
                        ),
                ),
                if (_c.canvas.isNotEmpty) ...[
                  SizedBox(
                    height: 120,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _PreviewCanvas(nodes: _c.canvas),
                    ),
                  ),
                  if (_c.events.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _BeatStrip(
                        events: _c.events,
                        durationMs: math.max(1, _c.mixDurationMs),
                        playheadMs: _c.mixer.playheadMs,
                      ),
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: PrimaryButton(
                    text: _c.busy
                        ? '处理中…'
                        : playing
                            ? '停止'
                            : '生成阿卡贝拉并试听',
                    enabled: !_c.busy && (_c.canPlay || playing),
                    onPressed: () async {
                      if (playing) {
                        await _c.stopMix();
                        return;
                      }
                      await _c.generateAndPlay();
                      if (_c.statusMessage != null) {
                        await _snack(_c.statusMessage!);
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SecondaryButton(
                    text: '导出作品',
                    onPressed: _c.canvas.isEmpty
                        ? null
                        : () async {
                            try {
                              final f = await _c.exportWork();
                              await _snack('已导出\n${f.parent.path}');
                            } catch (e) {
                              await _snack('$e');
                            }
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

class _SelectTile extends StatelessWidget {
  const _SelectTile({
    required this.source,
    required this.selected,
    required this.isPrimary,
    required this.onTap,
  });

  final LabSoundSource source;
  final bool selected;
  final bool isPrimary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sec = (source.durationMs / 1000).ceil();
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: selected
                  ? AppColors.accent
                  : AppColors.borderSubtle,
              width: selected ? 1.6 : 1,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: source.coverPath != null
                            ? Image.file(
                                File(source.coverPath!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => SoundVisualCanvas(
                                  seed: source.coverSeed,
                                  mode: SoundVisualMode.complete,
                                ),
                              )
                            : SoundVisualCanvas(
                                seed: source.coverSeed,
                                mode: SoundVisualMode.complete,
                              ),
                      ),
                    ),
                    if (selected)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPrimary ? Icons.star : Icons.check,
                            size: 12,
                            color: AppColors.accentOn,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                source.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${source.kindLabel} · ${sec}s',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
              if (isPrimary)
                const Text(
                  '主声音',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewCanvas extends StatelessWidget {
  const _PreviewCanvas({required this.nodes});
  final List<LabCanvasNode> nodes;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          return Stack(
            children: [
              Center(
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accent, width: 1.2),
                    color: AppColors.accent.withValues(alpha: 0.1),
                  ),
                  child: const Icon(Icons.hearing,
                      size: 14, color: AppColors.accent),
                ),
              ),
              ...nodes.map((n) {
                final left = (n.nx + 1) / 2 * c.maxWidth - 22;
                final top = (n.ny + 1) / 2 * c.maxHeight - 22;
                return Positioned(
                  left: left,
                  top: top,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: n.isPrimary
                            ? AppColors.accent
                            : AppColors.border,
                        width: n.isPrimary ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SoundVisualCanvas(
                      seed: n.source.coverSeed,
                      mode: SoundVisualMode.complete,
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _BeatStrip extends StatelessWidget {
  const _BeatStrip({
    required this.events,
    required this.durationMs,
    required this.playheadMs,
  });

  final List<BeatEvent> events;
  final int durationMs;
  final int playheadMs;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: CustomPaint(
        painter: _StripPainter(
          events: events,
          durationMs: durationMs,
          playheadMs: playheadMs,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.events,
    required this.durationMs,
    required this.playheadMs,
  });

  final List<BeatEvent> events;
  final int durationMs;
  final int playheadMs;

  static const _palette = [
    AppColors.accent,
    AppColors.accentSoft,
    Color(0xFF8AB8FF),
    Color(0xFFF2C879),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      Paint()..color = AppColors.surface2,
    );
    for (final e in events) {
      final x0 = e.timeMs / durationMs * size.width;
      final x1 = (e.timeMs + e.playDurationMs) / durationMs * size.width;
      final color = _palette[e.sourceIndex % _palette.length]
          .withValues(alpha: e.isDownbeat ? 0.85 : 0.45);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x0, 6, math.max(x0 + 2, x1), size.height - 6),
          const Radius.circular(3),
        ),
        Paint()..color = color,
      );
    }
    final px = playheadMs / durationMs * size.width;
    canvas.drawLine(
      Offset(px, 0),
      Offset(px, size.height),
      Paint()
        ..color = AppColors.accentHighlight
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _StripPainter old) =>
      old.playheadMs != playheadMs || old.events != events;
}
