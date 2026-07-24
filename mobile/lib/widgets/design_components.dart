import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/sound_repository.dart';
import '../services/auth_service.dart';
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
          backgroundColor: active ? AppColors.accent : AppColors.surface2,
          foregroundColor: active ? AppColors.accentOn : AppColors.textTertiary,
          disabledBackgroundColor: AppColors.surface2,
          disabledForegroundColor: AppColors.textTertiary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          elevation: 0,
        ),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.danger = false,
  });

  final String text;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.accent;
    return SizedBox(
      width: double.infinity,
      height: AppSizes.buttonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: danger ? AppColors.error.withValues(alpha: 0.5) : AppColors.border),
          backgroundColor: AppColors.surface1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
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
      SoundStatus.drafted => (
          '已暂存',
          AppColors.surface2,
          AppColors.textSecondary,
        ),
      SoundStatus.writing || SoundStatus.chainPending => (
          '处理中',
          AppColors.info.withValues(alpha: 0.16),
          AppColors.info,
        ),
      SoundStatus.writeFailed || SoundStatus.chainFailed => (
          '失败',
          AppColors.error.withValues(alpha: 0.16),
          AppColors.error,
        ),
      SoundStatus.collected => (
          '已收藏',
          AppColors.accent.withValues(alpha: 0.14),
          AppColors.accent,
        ),
    };
    return Container(
      height: AppSizes.statusChipHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class AccountAvatarButton extends StatelessWidget {
  const AccountAvatarButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (context, _) {
        final user = AuthService.instance.currentUser;
        final loggedIn = user != null;
        return GestureDetector(
          onTap: () => context.push('/account'),
          child: Container(
            width: AppSizes.avatar,
            height: AppSizes.avatar,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface2,
              border: Border.all(
                color: loggedIn ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border,
              ),
            ),
            alignment: Alignment.center,
            child: loggedIn
                ? Text(
                    user.initial,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  )
                : const Icon(
                    Icons.person_outline,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
          ),
        );
      },
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.showAccount = true,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showAccount;

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
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
          if (showAccount) ...[
            if (trailing != null) const SizedBox(width: 8),
            const AccountAvatarButton(),
          ],
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
                color: active
                    ? AppColors.accent.withValues(alpha: 0.15)
                    : AppColors.surface1,
                borderRadius: BorderRadius.circular(50),
                border: Border.all(
                  color: active ? AppColors.accent.withValues(alpha: 0.4) : AppColors.border,
                ),
              ),
              child: Text(
                option,
                style: TextStyle(
                  color: active ? AppColors.accent : AppColors.textTertiary,
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

class _RecordFabState extends State<RecordFab>
    with SingleTickerProviderStateMixin {
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
          width: AppSizes.recordButton + 24,
          height: AppSizes.recordButton + 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.recording)
                Container(
                  width: AppSizes.recordButton * ripple,
                  height: AppSizes.recordButton * ripple,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  width: AppSizes.recordButton,
                  height: AppSizes.recordButton,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: widget.recording
                      ? Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppColors.accentOn,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )
                      : Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: AppColors.accentOn,
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
  const BottomNavBar({
    super.key,
    required this.selected,
    required this.onSelect,
  });
  final int selected;
  final ValueChanged<int> onSelect;

  static const _tabs = ['Record', 'Drafts', 'Collection'];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bottomNav,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppSizes.bottomNav,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageHorizontal,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(_tabs.length, (index) {
                final active = selected == index;
                return GestureDetector(
                  onTap: () => onSelect(index),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text(
                      _tabs[index],
                      style: TextStyle(
                        color: active
                            ? AppColors.accent
                            : AppColors.textTertiary,
                        fontSize: 13,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class TimerText extends StatelessWidget {
  const TimerText({super.key, required this.seconds, this.dark = true});
  final int seconds;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return Text(
      '$m:${s.toString().padLeft(2, '0')}',
      style: const TextStyle(
        color: AppColors.textPrimary,
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
          color: AppColors.textPrimary,
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
          Text(
            label,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SpTextField extends StatelessWidget {
  const SpTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.obscure = false,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final bool obscure;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) SectionLabel(label!),
        TextField(
          controller: controller,
          obscureText: obscure,
          maxLines: obscure ? 1 : maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            counterStyle: const TextStyle(color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }
}

class LoginHintCard extends StatelessWidget {
  const LoginHintCard({super.key, required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: InkWell(
          onTap: onLogin,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '登录后可写入声片、创建数字资产并跨设备保留收藏。',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '登录',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
