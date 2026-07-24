import 'package:flutter/material.dart';
import '../data/sound_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.enabled = true,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: AppSizes.buttonHeight,
      child: FilledButton(
        onPressed: active ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: active ? AppColors.primary500 : AppColors.surface100,
          foregroundColor: active ? AppColors.ink950 : AppColors.ink400,
          disabledBackgroundColor: AppColors.surface100,
          disabledForegroundColor: AppColors.ink400,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          elevation: 0,
        ),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.text, required this.onPressed});

  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppSizes.buttonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink950,
          side: const BorderSide(color: AppColors.line200),
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
        ),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final SoundStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      SoundStatus.drafted => ('已暂存', AppColors.surface100, AppColors.ink950),
      SoundStatus.writing || SoundStatus.chainPending => ('处理中', const Color(0xFFE8F0FE), AppColors.info),
      SoundStatus.writeFailed || SoundStatus.chainFailed => ('失败', const Color(0xFFFDECEC), AppColors.error),
      SoundStatus.collected => ('已收藏', AppColors.primary100, AppColors.primary700),
    };
    return Container(
      height: AppSizes.statusChipHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(50)),
      alignment: Alignment.center,
      child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.item,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: const TextStyle(color: AppColors.ink400, fontSize: 13)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
      child: Wrap(
        spacing: AppSpacing.chip,
        runSpacing: AppSpacing.chip,
        children: options.map((option) {
          final active = option == selected;
          return GestureDetector(
            onTap: () => onSelect(option),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.primary100 : AppColors.surface100,
                borderRadius: BorderRadius.circular(50),
                border: Border.all(
                  color: active ? AppColors.primary500 : AppColors.surface100,
                ),
              ),
              child: Text(
                option,
                style: TextStyle(
                  color: active ? AppColors.primary700 : AppColors.ink600,
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class RecordFab extends StatefulWidget {
  const RecordFab({super.key, required this.recording, required this.onTap});
  final bool recording;
  final VoidCallback onTap;

  @override
  State<RecordFab> createState() => _RecordFabState();
}

class _RecordFabState extends State<RecordFab> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final ripple = 0.85 + 0.3 * _controller.value;
        return SizedBox(
          width: AppSizes.recordButton + 28,
          height: AppSizes.recordButton + 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.recording) ...[
                Container(
                  width: AppSizes.recordButton * ripple,
                  height: AppSizes.recordButton * ripple,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary500.withValues(alpha: 0.25)),
                  ),
                ),
              ],
              GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  width: AppSizes.recordButton,
                  height: AppSizes.recordButton,
                  decoration: const BoxDecoration(
                    color: AppColors.primary500,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: widget.recording
                      ? Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: AppColors.ink950,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )
                      : Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: AppColors.ink950,
                            shape: BoxShape.circle,
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key, required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  static const _tabs = ['Record', 'Drafts', 'Collection'];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, color: AppColors.line200.withValues(alpha: 0.7)),
        SizedBox(
          height: AppSizes.bottomNav,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(_tabs.length, (index) {
                final active = selected == index;
                return GestureDetector(
                  onTap: () => onSelect(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary100 : Colors.transparent,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      _tabs[index],
                      style: TextStyle(
                        color: active ? AppColors.ink950 : AppColors.ink400,
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

class TimerText extends StatelessWidget {
  const TimerText({super.key, required this.seconds, this.dark = false});
  final int seconds;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return Text(
      '$m:${s.toString().padLeft(2, '0')}',
      style: TextStyle(
        color: dark ? AppColors.darkText : AppColors.ink950,
        fontSize: 40,
        fontWeight: FontWeight.w500,
        fontFamily: 'monospace',
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.ink950,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class MetaRow extends StatelessWidget {
  const MetaRow({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.ink400, fontSize: 13)),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.ink800,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
