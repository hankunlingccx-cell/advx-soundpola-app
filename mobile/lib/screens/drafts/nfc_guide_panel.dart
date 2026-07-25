import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';

/// Drafts 页内 NFC 指引 / 操作区状态。
enum NfcGuidePhase {
  howto,
  dimmed,
  waiting,
  found,
  pressing,
  complete,
  interrupted,
  alreadyBound,
  empty,
}

class NfcGuidePanel extends StatelessWidget {
  const NfcGuidePanel({
    super.key,
    required this.phase,
    required this.breath,
    this.soundTitle,
    this.progress = 0,
    this.chaining = false,
    this.onStartDetect,
    this.onCancelWrite,
    this.onRetrieve,
    this.onRetry,
    this.onDetectOther,
    this.onViewCollection,
    this.onContinue,
    this.onStartRecord,
    this.autoListening = false,
  });

  final NfcGuidePhase phase;
  final Animation<double> breath;
  final String? soundTitle;
  final double progress;
  final bool chaining;
  final VoidCallback? onStartDetect;
  final VoidCallback? onCancelWrite;
  final VoidCallback? onRetrieve;
  final VoidCallback? onRetry;
  final VoidCallback? onDetectOther;
  final VoidCallback? onViewCollection;
  final VoidCallback? onContinue;
  final VoidCallback? onStartRecord;
  /// 系统已自动监听 NFC 时，主按钮改为「取消写入」。
  final bool autoListening;

  @override
  Widget build(BuildContext context) {
    final dim = phase == NfcGuidePhase.dimmed;
    return AnimatedOpacity(
      duration: AppMotion.fast,
      opacity: dim ? 0.28 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: AnimatedSwitcher(
          duration: AppMotion.normal,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(
            key: ValueKey(phase),
            child: _buildBody(context),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return switch (phase) {
      NfcGuidePhase.howto || NfcGuidePhase.dimmed => _HowtoBody(),
      NfcGuidePhase.waiting => _WaitingBody(
          breath: breath,
          autoListening: autoListening,
          onStartDetect: onStartDetect,
          onCancelWrite: onCancelWrite,
          onRetrieve: onRetrieve,
        ),
      NfcGuidePhase.found => const _FoundBody(),
      NfcGuidePhase.pressing => _PressingBody(progress: progress),
      NfcGuidePhase.complete => _CompleteBody(
          soundTitle: soundTitle ?? '',
          chaining: chaining,
          onViewCollection: onViewCollection,
          onContinue: onContinue,
        ),
      NfcGuidePhase.interrupted => _InterruptedBody(
          onRetry: onRetry,
          onRetrieve: onRetrieve,
        ),
      NfcGuidePhase.alreadyBound => _BoundBody(onDetectOther: onDetectOther),
      NfcGuidePhase.empty => _EmptyBody(onStartRecord: onStartRecord),
    };
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.code, required this.title});

  final String code;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          code,
          style: const TextStyle(
            fontFamily: 'Courier',
            color: AppColors.accent,
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _HowtoBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead(code: 'HOW TO PRESS', title: '如何封存声音'),
        const SizedBox(height: 8),
        Text(
          '拖动一张声音卡片插入设备，\n然后将实体声片靠近手机 NFC 区域。',
          style: TextStyle(
            color: AppColors.textTertiary.withValues(alpha: 0.95),
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _PhoneNfcDiagram extends StatelessWidget {
  const _PhoneNfcDiagram({
    required this.breath,
    this.pulse = true,
  });

  final Animation<double> breath;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final hint = Platform.isIOS
        ? '感应区多在机身上半部背面'
        : '感应区多在机身背部中央偏上';

    return AnimatedBuilder(
      animation: breath,
      builder: (context, _) {
        final wave = pulse ? (0.15 + 0.35 * breath.value) : 0.2;
        return Column(
          children: [
            SizedBox(
              height: 88,
              child: CustomPaint(
                size: const Size(160, 88),
                painter: _PhoneNfcPainter(
                  accent: false,
                  waveAlpha: wave,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PhoneNfcPainter extends CustomPainter {
  _PhoneNfcPainter({required this.accent, required this.waveAlpha});

  final bool accent;
  final double waveAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final phone = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * 0.38, size.height * 0.5),
        width: 44,
        height: 78,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      phone,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = AppColors.structure,
    );
    // 常见感应区示意（上半）
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * 0.38, size.height * 0.32),
          width: 28,
          height: 18,
        ),
        const Radius.circular(3),
      ),
      Paint()
        ..color = (accent ? AppColors.accent : AppColors.structure)
            .withValues(alpha: accent ? 0.35 : 0.4),
    );

    // 声片圆
    final discC = Offset(size.width * 0.72, size.height * 0.48);
    canvas.drawCircle(
      discC,
      16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = accent ? AppColors.accent : AppColors.structure,
    );
    canvas.drawCircle(
      discC,
      4,
      Paint()..color = (accent ? AppColors.accent : AppColors.structure)
          .withValues(alpha: 0.5),
    );

    // 低亮度感应波纹
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(
        discC,
        16.0 + i * 7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = AppColors.accent.withValues(alpha: waveAlpha / i),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PhoneNfcPainter old) =>
      old.accent != accent || old.waveAlpha != waveAlpha;
}

class _WaitingBody extends StatefulWidget {
  const _WaitingBody({
    required this.breath,
    required this.autoListening,
    this.onStartDetect,
    this.onCancelWrite,
    this.onRetrieve,
  });

  final Animation<double> breath;
  final bool autoListening;
  final VoidCallback? onStartDetect;
  final VoidCallback? onCancelWrite;
  final VoidCallback? onRetrieve;

  @override
  State<_WaitingBody> createState() => _WaitingBodyState();
}

class _WaitingBodyState extends State<_WaitingBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    // 感应波纹约每 3 秒一次
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead(code: 'READY TO PRESS', title: '准备写入实体声片'),
        const SizedBox(height: 8),
        const Text(
          '将一枚未绑定的 SoundPola 声片\n贴近手机背部的 NFC 感应区域。',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: _PhoneNfcDiagram(breath: _pulse, pulse: true),
        ),
        const SizedBox(height: 12),
        if (widget.autoListening)
          SecondaryButton(
            text: '取消写入',
            onPressed: widget.onCancelWrite,
          )
        else
          PrimaryButton(
            text: '开始检测 NFC',
            onPressed: widget.onStartDetect,
          ),
        const SizedBox(height: 8),
        SecondaryButton(
          text: '取回声音',
          onPressed: widget.onRetrieve,
        ),
        const SizedBox(height: 8),
        const Text(
          '每枚实体声片只能永久绑定一段声音',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _FoundBody extends StatelessWidget {
  const _FoundBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHead(code: 'SOUND PIECE FOUND', title: '已检测到实体声片'),
        SizedBox(height: 8),
        Text(
          '请保持声片位置不动。',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _PressingBody extends StatelessWidget {
  const _PressingBody({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).round().clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHead(
          code: 'PRESSING SOUND · $pct%',
          title: '正在写入声音',
        ),
        const SizedBox(height: 8),
        const Text(
          '请勿移动实体声片。',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 14),
        CustomPaint(
          size: const Size(double.infinity, 14),
          painter: _SegmentProgressPainter(progress: progress),
        ),
      ],
    );
  }
}

class _SegmentProgressPainter extends CustomPainter {
  _SegmentProgressPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const segments = 16;
    const gap = 3.0;
    final totalGap = gap * (segments - 1);
    final w = (size.width - totalGap) / segments;
    final filled = (progress.clamp(0.0, 1.0) * segments).ceil();

    for (var i = 0; i < segments; i++) {
      final x = i * (w + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 2, w, size.height - 4),
          const Radius.circular(1.5),
        ),
        Paint()
          ..color = i < filled
              ? AppColors.accent
              : AppColors.structure.withValues(alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentProgressPainter old) =>
      old.progress != progress;
}

class _CompleteBody extends StatelessWidget {
  const _CompleteBody({
    required this.soundTitle,
    required this.chaining,
    this.onViewCollection,
    this.onContinue,
  });

  final String soundTitle;
  final bool chaining;
  final VoidCallback? onViewCollection;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead(code: 'PRESS COMPLETE', title: '声音已完成封存'),
        const SizedBox(height: 8),
        Text(
          chaining
              ? '「$soundTitle」已与实体声片绑定，\n正在生成正式收藏资产。'
              : '「$soundTitle」已与实体声片绑定。',
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          text: chaining ? '查看生成进度' : '查看 Collection',
          onPressed: onViewCollection,
        ),
        const SizedBox(height: 8),
        SecondaryButton(
          text: '继续写入下一张',
          onPressed: onContinue,
        ),
      ],
    );
  }
}

class _InterruptedBody extends StatelessWidget {
  const _InterruptedBody({this.onRetry, this.onRetrieve});

  final VoidCallback? onRetry;
  final VoidCallback? onRetrieve;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead(code: 'PRESS INTERRUPTED', title: '写入未完成'),
        const SizedBox(height: 8),
        const Text(
          '请重新贴近实体声片，\n并在写入过程中保持位置不动。',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        PrimaryButton(text: '重新检测', onPressed: onRetry),
        const SizedBox(height: 8),
        SecondaryButton(text: '取回声音', onPressed: onRetrieve),
      ],
    );
  }
}

class _BoundBody extends StatelessWidget {
  const _BoundBody({this.onDetectOther});

  final VoidCallback? onDetectOther;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead(
          code: 'SOUND PIECE ALREADY BOUND',
          title: '这枚声片已经封存过声音',
        ),
        const SizedBox(height: 8),
        const Text(
          '每枚 SoundPola 声片只能永久绑定一次，\n请更换一枚未绑定声片。',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        PrimaryButton(text: '检测其他声片', onPressed: onDetectOther),
      ],
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({this.onStartRecord});

  final VoidCallback? onStartRecord;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead(code: 'NO SOUND DRAFTS', title: '还没有等待封存的声音'),
        const SizedBox(height: 8),
        const Text(
          '录制完成的声音会先暂存在这里，\n之后可以插入设备并写入实体声片。',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        PrimaryButton(text: '去录一段声音', onPressed: onStartRecord),
      ],
    );
  }
}
