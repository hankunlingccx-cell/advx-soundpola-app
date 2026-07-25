import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/disc_rarity.dart';
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

/// 稀有度角标；null / pending 显示「待揭晓」。
class RarityChip extends StatelessWidget {
  const RarityChip({
    super.key,
    this.rarity,
    this.pending = false,
    this.compact = false,
  });

  final DiscRarity? rarity;
  final bool pending;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final showPending = pending || rarity == null;
    final label = showPending ? '待揭晓' : rarity!.code;
    final Color fg;
    final Color bg;
    if (showPending) {
      fg = AppColors.textTertiary;
      bg = AppColors.surface2;
    } else {
      (bg, fg) = rarityPalette(rarity!);
    }
    return Container(
      height: compact ? 22 : AppSizes.statusChipHeight,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: showPending
              ? AppColors.borderSubtle
              : fg.withValues(alpha: 0.35),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w600,
          letterSpacing: showPending ? 0 : 0.4,
        ),
      ),
    );
  }
}

/// 游戏式稀有度展示：大号代号 + 中文名 + 等级条，用于声片信息区。
class RarityShowcase extends StatelessWidget {
  const RarityShowcase({super.key, this.rarity});

  final DiscRarity? rarity;

  static const _tiers = DiscRarity.values;

  @override
  Widget build(BuildContext context) {
    final pending = rarity == null;
    final accent = pending
        ? AppColors.textTertiary
        : rarityPalette(rarity!).$2;
    final fill = pending
        ? AppColors.surface2
        : rarityPalette(rarity!).$1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
        boxShadow: pending
            ? null
            : [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 16,
                  spreadRadius: 0,
                ),
              ],
      ),
      child: Column(
        children: [
          Text(
            pending ? '?' : rarity!.code,
            style: TextStyle(
              color: accent,
              fontSize: pending ? 28 : 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.4,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            pending ? '稀有度待揭晓' : rarity!.label,
            style: TextStyle(
              color: accent,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final tier in _tiers)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Text(
                    tier.code,
                    style: TextStyle(
                      fontSize: !pending && tier == rarity ? 13 : 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: pending
                          ? AppColors.textTertiary.withValues(alpha: 0.45)
                          : tier.index <= rarity!.index
                              ? (tier == rarity
                                  ? accent
                                  : accent.withValues(alpha: 0.55))
                              : AppColors.textTertiary.withValues(alpha: 0.35),
                    ),
                  ),
                ),
            ],
          ),
          if (!pending) ...[
            const SizedBox(height: 8),
            Text(
              '由实体声片出厂决定',
              style: TextStyle(
                color: accent.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

(Color, Color) rarityPalette(DiscRarity rarity) => switch (rarity) {
      DiscRarity.n => (AppColors.surface2, AppColors.textSecondary),
      DiscRarity.r => (
          AppColors.accent.withValues(alpha: 0.12),
          AppColors.accent,
        ),
      DiscRarity.sr => (
          const Color(0xFF4FA9E8).withValues(alpha: 0.16),
          const Color(0xFF4FA9E8),
        ),
      DiscRarity.ssr => (
          AppColors.accent.withValues(alpha: 0.22),
          AppColors.accent,
        ),
    };

class AccountAvatarButton extends StatelessWidget {
  const AccountAvatarButton({super.key, this.compact = false});

  /// 圆形图标按钮，降低账户入口视觉权重。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (context, _) {
        final loggedIn = AuthService.instance.currentUser != null;
        return Tooltip(
          message: '账户',
          child: GestureDetector(
            onTap: () => context.push('/account'),
            child: Semantics(
              label: '账户',
              button: true,
              child: compact
                  ? Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.device,
                        border: Border.all(color: AppColors.structure),
                      ),
                      child: Icon(
                        loggedIn ? Icons.person : Icons.person_outline,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                    )
                  : Container(
                      height: AppSizes.avatar,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(AppSizes.avatar / 2),
                        color: AppColors.surface2,
                        border: Border.all(
                          color: loggedIn
                              ? AppColors.accent.withValues(alpha: 0.5)
                              : AppColors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            loggedIn ? Icons.person : Icons.person_outline,
                            size: 16,
                            color: loggedIn
                                ? AppColors.accent
                                : AppColors.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '账户',
                            style: TextStyle(
                              color: loggedIn
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
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

enum RecordFabState { idle, recording, paused }

class RecordFab extends StatefulWidget {
  const RecordFab({
    super.key,
    required this.onTap,
    this.state = RecordFabState.idle,
  });

  final VoidCallback onTap;
  final RecordFabState state;

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
    final fabState = widget.state;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final ripple = 0.85 + 0.3 * _controller.value;
        final fill = switch (fabState) {
          RecordFabState.idle => AppColors.accent.withValues(alpha: 0.92),
          RecordFabState.recording => AppColors.accent,
          RecordFabState.paused => AppColors.accent.withValues(alpha: 0.55),
        };
        return SizedBox(
          width: AppSizes.recordButton + 28,
          height: AppSizes.recordButton + 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Soft mint halo ties FAB to visualization.
              Container(
                width: AppSizes.recordButton + 18,
                height: AppSizes.recordButton + 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent.withValues(
                        alpha: fabState == RecordFabState.recording
                            ? 0.18
                            : (fabState == RecordFabState.paused ? 0.08 : 0.1),
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              if (fabState == RecordFabState.recording)
                Container(
                  width: AppSizes.recordButton * ripple,
                  height: AppSizes.recordButton * ripple,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.28),
                    ),
                  ),
                ),
              if (fabState == RecordFabState.paused)
                Container(
                  width: AppSizes.recordButton + 8,
                  height: AppSizes.recordButton + 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                ),
              GestureDetector(
                onTap: widget.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  width: AppSizes.recordButton,
                  height: AppSizes.recordButton,
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                    border: fabState == RecordFabState.paused
                        ? Border.all(
                            color: AppColors.accentHighlight.withValues(alpha: 0.5),
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: switch (fabState) {
                    RecordFabState.recording => Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.accentOn,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    RecordFabState.paused => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 4,
                            height: 16,
                            color: AppColors.accentOn,
                          ),
                          const SizedBox(width: 5),
                          Container(
                            width: 4,
                            height: 16,
                            color: AppColors.accentOn,
                          ),
                        ],
                      ),
                    RecordFabState.idle => Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: AppColors.accentOn,
                          shape: BoxShape.circle,
                        ),
                      ),
                  },
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

  static const _tabs = [
    (Icons.fiber_manual_record_outlined, Icons.fiber_manual_record, 'Record'),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Drafts'),
    (Icons.album_outlined, Icons.album, 'Collection'),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bottomNav,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppSizes.bottomNav,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.structure, width: 0.8),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: List.generate(_tabs.length, (index) {
                  final active = selected == index;
                  final tab = _tabs[index];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onSelect(index),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 当前项上方短小状态刻度
                          Container(
                            width: active ? 16 : 0,
                            height: 2,
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                          Icon(
                            active ? tab.$2 : tab.$1,
                            size: 18,
                            color: active
                                ? AppColors.accent
                                : AppColors.textTertiary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tab.$3,
                            style: TextStyle(
                              color: active
                                  ? AppColors.accent
                                  : AppColors.textTertiary,
                              fontSize: 11,
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.w400,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
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
