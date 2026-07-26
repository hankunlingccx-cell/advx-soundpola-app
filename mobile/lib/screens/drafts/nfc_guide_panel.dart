import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/design_components.dart';

/// Drafts 页内 NFC 封存引导（云端准备无需贴近 → 单次贴近检查并写入）。
enum NfcGuidePhase {
  howto,
  dimmed,
  /// 开始封存 / 等待云端准备
  checkPrompt,
  /// （保留）识别中
  checking,
  /// （保留）验证成功
  verified,
  /// 云端：上传
  cloudUploading,
  /// 云端：处理
  cloudProcessing,
  /// 等待单次贴近（检查＋写入）
  writePrompt,
  /// 正在写入
  writing,
  /// 写入成功，可移开
  writeSuccess,
  /// 上链中
  chaining,
  complete,
  cardAlreadyBound,
  cardInvalid,
  cloudFailed,
  wrongCard,
  writeFailed,
  chainFailed,
  empty,
}

enum CloudPrepStage { upload, process, ready }

class NfcGuidePanel extends StatelessWidget {
  const NfcGuidePanel({
    super.key,
    required this.phase,
    required this.breath,
    this.soundTitle,
    this.cloudStage,
    this.statusHint,
    this.chaining = false,
    this.failReason,
    this.boundTitle,
    this.boundTimeLabel,
    this.boundContentId,
    this.onStartDetect,
    this.onCancelWrite,
    this.onRetrieve,
    this.onRetry,
    this.onDetectOther,
    this.onViewBoundSound,
    this.onViewCollection,
    this.onContinue,
    this.onStartRecord,
    this.onRetryChain,
    this.onLater,
    this.autoListening = false,
    this.isSimulation = false,
  });

  final NfcGuidePhase phase;
  final Animation<double> breath;
  final String? soundTitle;
  final CloudPrepStage? cloudStage;
  final String? statusHint;
  final bool chaining;
  final String? failReason;
  final String? boundTitle;
  final String? boundTimeLabel;
  final String? boundContentId;
  final VoidCallback? onStartDetect;
  final VoidCallback? onCancelWrite;
  final VoidCallback? onRetrieve;
  final VoidCallback? onRetry;
  final VoidCallback? onDetectOther;
  final VoidCallback? onViewBoundSound;
  final VoidCallback? onViewCollection;
  final VoidCallback? onContinue;
  final VoidCallback? onStartRecord;
  final VoidCallback? onRetryChain;
  final VoidCallback? onLater;
  final bool autoListening;
  final bool isSimulation;

  @override
  Widget build(BuildContext context) {
    final dim = phase == NfcGuidePhase.dimmed;
    final idle = phase == NfcGuidePhase.howto ||
        phase == NfcGuidePhase.dimmed ||
        phase == NfcGuidePhase.empty;
    final fill = idle ? 0.08 : 0.16;

    return AnimatedOpacity(
      duration: AppMotion.fast,
      opacity: dim ? 0.4 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: AppMotion.normal,
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: fill),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withValues(alpha: idle ? 0.14 : 0.28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
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
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return switch (phase) {
      NfcGuidePhase.howto || NfcGuidePhase.dimmed => const _HowtoBody(),
      NfcGuidePhase.checkPrompt => _CheckPromptBody(
          breath: breath,
          autoListening: autoListening,
          isSimulation: isSimulation,
          onStartDetect: onStartDetect,
          onCancelWrite: onCancelWrite,
          onRetrieve: onRetrieve,
        ),
      NfcGuidePhase.checking => _CheckingBody(breath: breath),
      NfcGuidePhase.verified => const _VerifiedBody(),
      NfcGuidePhase.cloudUploading || NfcGuidePhase.cloudProcessing =>
        _CloudBody(
          stage: cloudStage ??
              (phase == NfcGuidePhase.cloudUploading
                  ? CloudPrepStage.upload
                  : CloudPrepStage.process),
          onRetrieve: onRetrieve,
          isSimulation: isSimulation,
          statusHint: statusHint,
        ),
      NfcGuidePhase.writePrompt => _WritePromptBody(
          breath: breath,
          autoListening: autoListening,
          onCancelWrite: onCancelWrite,
          onRetrieve: onRetrieve,
          isSimulation: isSimulation,
        ),
      NfcGuidePhase.writing => const _WritingBody(),
      NfcGuidePhase.writeSuccess => const _WriteSuccessBody(),
      NfcGuidePhase.chaining => _ChainingBody(soundTitle: soundTitle ?? ''),
      NfcGuidePhase.complete => _CompleteBody(
          soundTitle: soundTitle ?? '',
          chaining: chaining,
          onViewCollection: onViewCollection,
          onContinue: onContinue,
        ),
      NfcGuidePhase.cardAlreadyBound => _BoundBody(
          title: boundTitle,
          timeLabel: boundTimeLabel,
          contentId: boundContentId,
          onDetectOther: onDetectOther,
          onViewBoundSound: onViewBoundSound,
        ),
      NfcGuidePhase.cardInvalid => _FailBody(
          code: 'CARD INVALID',
          title: '未能识别声片',
          message: failReason ?? '请调整声片位置后重试',
          primaryLabel: '重新识别',
          onPrimary: onRetry,
          onRetrieve: onRetrieve,
        ),
      NfcGuidePhase.cloudFailed => _FailBody(
          code: 'CLOUD FAILED',
          title: '云端准备失败',
          message: failReason ?? '请检查网络后重试上传，无需贴近声片。',
          primaryLabel: '重试云端准备',
          onPrimary: onRetry,
          onRetrieve: onRetrieve,
          note: '此步骤不需要 NFC',
        ),
      NfcGuidePhase.wrongCard => _FailBody(
          code: 'WRONG CARD',
          title: '这不是刚才验证的声片',
          message: '请使用已完成检查的声片',
          primaryLabel: '再次贴近正确声片',
          onPrimary: onRetry,
          onRetrieve: onRetrieve,
        ),
      NfcGuidePhase.writeFailed => _FailBody(
          code: 'WRITE FAILED',
          title: '声片写入未完成',
          message: failReason ?? '请保持贴近后重试写入。云端内容已保留，不会重新上传。',
          primaryLabel: '重试写入',
          onPrimary: onRetry,
          onRetrieve: onRetrieve,
          note: '只会重试 NFC 写入，不会重新上传',
        ),
      NfcGuidePhase.chainFailed => _ChainFailBody(
          soundTitle: soundTitle ?? '',
          failReason: failReason,
          onRetryChain: onRetryChain,
          onLater: onLater,
          onViewCollection: onViewCollection,
        ),
      NfcGuidePhase.empty => _EmptyBody(onStartRecord: onStartRecord),
    };
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({
    required this.code,
    required this.title,
    this.stepLabel,
  });

  final String code;
  final String title;
  final String? stepLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                code,
                style: TextStyle(
                  fontFamily: 'Courier',
                  color: AppColors.accent.withValues(alpha: 0.95),
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (stepLabel != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.28),
                  ),
                ),
                child: Text(
                  stepLabel!,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _SimBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'SIMULATION',
          style: TextStyle(
            fontFamily: 'Courier',
            color: AppColors.textTertiary.withValues(alpha: 0.8),
            fontSize: 9,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class _HowtoBody extends StatelessWidget {
  const _HowtoBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead(code: 'HOW TO PRESS', title: '如何封存声音'),
        const SizedBox(height: 8),
        Text(
          '拖动一张声音卡片插入设备，\n然后将空白声片轻触手机 NFC 区域。',
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
    this.mode = _NfcVisualMode.pulse,
  });

  final Animation<double> breath;
  final _NfcVisualMode mode;

  @override
  Widget build(BuildContext context) {
    final hint = Platform.isIOS
        ? '感应区多在机身上半部背面'
        : '感应区多在机身背部中央偏上';

    return AnimatedBuilder(
      animation: breath,
      builder: (context, _) {
        final wave = switch (mode) {
          _NfcVisualMode.pulse => 0.18 + 0.42 * breath.value,
          _NfcVisualMode.glow => 0.35,
          _NfcVisualMode.off => 0.0,
        };
        return Column(
          children: [
            SizedBox(
              height: 88,
              child: CustomPaint(
                size: const Size(160, 88),
                painter: _PhoneNfcPainter(
                  accent: mode != _NfcVisualMode.off,
                  waveAlpha: wave,
                  discAway: mode == _NfcVisualMode.off,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              mode == _NfcVisualMode.off ? '无需贴近 NFC' : hint,
              style: TextStyle(
                color: mode == _NfcVisualMode.off
                    ? AppColors.accent.withValues(alpha: 0.85)
                    : AppColors.textTertiary,
                fontSize: 11,
                fontWeight:
                    mode == _NfcVisualMode.off ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _NfcVisualMode { pulse, glow, off }

class _PhoneNfcPainter extends CustomPainter {
  _PhoneNfcPainter({
    required this.accent,
    required this.waveAlpha,
    this.discAway = false,
  });

  final bool accent;
  final double waveAlpha;
  final bool discAway;

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
            .withValues(alpha: accent ? 0.4 : 0.35),
    );

    final discC = Offset(
      size.width * (discAway ? 0.82 : 0.72),
      size.height * (discAway ? 0.72 : 0.48),
    );
    canvas.drawCircle(
      discC,
      16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = accent && !discAway ? AppColors.accent : AppColors.structure,
    );
    canvas.drawCircle(
      discC,
      4,
      Paint()
        ..color = (accent && !discAway ? AppColors.accent : AppColors.structure)
            .withValues(alpha: 0.5),
    );

    if (waveAlpha > 0.01 && !discAway) {
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
  }

  @override
  bool shouldRepaint(covariant _PhoneNfcPainter old) =>
      old.accent != accent ||
      old.waveAlpha != waveAlpha ||
      old.discAway != discAway;
}

class _CheckPromptBody extends StatelessWidget {
  const _CheckPromptBody({
    required this.breath,
    required this.autoListening,
    required this.isSimulation,
    this.onStartDetect,
    this.onCancelWrite,
    this.onRetrieve,
  });

  final Animation<double> breath;
  final bool autoListening;
  final bool isSimulation;
  final VoidCallback? onStartDetect;
  final VoidCallback? onCancelWrite;
  final VoidCallback? onRetrieve;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isSimulation) _SimBadge(),
        const _SectionHead(
          code: 'READY TO PRESS',
          title: '准备封存声音',
        ),
        const SizedBox(height: 8),
        const Text(
          '若声音尚未上云，将先上传并生成链接（无需贴近声片）\n'
          '已预上传完成时，贴近声片即可直接检查并写入',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: _PhoneNfcDiagram(
            breath: breath,
            mode: _NfcVisualMode.off,
          ),
        ),
        const SizedBox(height: 12),
        if (autoListening)
          SecondaryButton(text: '取消', onPressed: onCancelWrite)
        else
          PrimaryButton(text: '开始准备', onPressed: onStartDetect),
        const SizedBox(height: 8),
        SecondaryButton(text: '取回声音', onPressed: onRetrieve),
      ],
    );
  }
}

class _CheckingBody extends StatelessWidget {
  const _CheckingBody({required this.breath});

  final Animation<double> breath;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead(
          code: 'CHECKING PIECE',
          title: '正在识别声片',
          stepLabel: '第 1 次，共 2 次',
        ),
        const SizedBox(height: 8),
        const Text(
          '请短暂保持贴近',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: _PhoneNfcDiagram(breath: breath, mode: _NfcVisualMode.pulse),
        ),
      ],
    );
  }
}

class _VerifiedBody extends StatelessWidget {
  const _VerifiedBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead(
          code: 'PIECE VERIFIED',
          title: '声片验证完成',
          stepLabel: '第 1 次，共 2 次',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.18),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.55)),
              ),
              child: const Icon(Icons.check_rounded, size: 18, color: AppColors.accent),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '现在可以移开声片',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '即将准备声音内容，无需持续贴近',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
      ],
    );
  }
}

class _CloudBody extends StatelessWidget {
  const _CloudBody({
    required this.stage,
    this.onRetrieve,
    this.isSimulation = false,
    this.statusHint,
  });

  final CloudPrepStage stage;
  final VoidCallback? onRetrieve;
  final bool isSimulation;
  final String? statusHint;

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('上传声音', stage.index >= CloudPrepStage.upload.index),
      ('生成声音内容', stage.index >= CloudPrepStage.process.index),
      ('等待写入', stage == CloudPrepStage.ready),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isSimulation) _SimBadge(),
        const _SectionHead(
          code: 'PREPARING MEMORY',
          title: '正在准备声音内容',
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
          ),
          child: const Text(
            '请移开声片 · 此步骤无需贴近 NFC',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          statusHint?.trim().isNotEmpty == true
              ? statusHint!
              : '正在上传并生成声片链接，完成后请贴近声片一次',
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < steps.length; i++) ...[
          _StageRow(
            index: i + 1,
            label: steps[i].$1,
            active: steps[i].$2,
            current: stage.index == i ||
                (stage == CloudPrepStage.ready && i == steps.length - 1),
          ),
          if (i < steps.length - 1) const SizedBox(height: 8),
        ],
        const SizedBox(height: 14),
        Center(
          child: _PhoneNfcDiagram(
            breath: const AlwaysStoppedAnimation(0.2),
            mode: _NfcVisualMode.off,
          ),
        ),
        const SizedBox(height: 12),
        SecondaryButton(text: '取回声音', onPressed: onRetrieve),
      ],
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.index,
    required this.label,
    required this.active,
    required this.current,
  });

  final int index;
  final String label;
  final bool active;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final color = current
        ? AppColors.accent
        : (active ? AppColors.textSecondary : AppColors.textTertiary);
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: current
                ? AppColors.accent.withValues(alpha: 0.2)
                : AppColors.surface2,
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: active && !current
              ? const Icon(Icons.check, size: 12, color: AppColors.accent)
              : Text(
                  '$index',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: current ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        if (current) ...[
          const Spacer(),
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: AppColors.accent.withValues(alpha: 0.85),
            ),
          ),
        ],
      ],
    );
  }
}

class _WritePromptBody extends StatelessWidget {
  const _WritePromptBody({
    required this.breath,
    required this.autoListening,
    this.onCancelWrite,
    this.onRetrieve,
    this.isSimulation = false,
  });

  final Animation<double> breath;
  final bool autoListening;
  final VoidCallback? onCancelWrite;
  final VoidCallback? onRetrieve;
  final bool isSimulation;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isSimulation) _SimBadge(),
        const _SectionHead(
          code: 'READY TO WRITE',
          title: '请贴近声片',
        ),
        const SizedBox(height: 8),
        const Text(
          '内容已准备完成\n贴近后将检查声片是否已写入，空白则完成封存\n写入完成前请保持贴近',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '只需贴近一次 · 检查并写入',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: _PhoneNfcDiagram(breath: breath, mode: _NfcVisualMode.glow),
        ),
        const SizedBox(height: 12),
        if (autoListening)
          SecondaryButton(text: '取消写入', onPressed: onCancelWrite),
        const SizedBox(height: 8),
        SecondaryButton(text: '取回声音', onPressed: onRetrieve),
      ],
    );
  }
}

class _WritingBody extends StatelessWidget {
  const _WritingBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHead(
          code: 'WRITING',
          title: '正在写入声片',
        ),
        SizedBox(height: 8),
        Text(
          '请保持贴近，不要移动',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _WriteSuccessBody extends StatelessWidget {
  const _WriteSuccessBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead(code: 'PRESSED', title: '声片写入完成'),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.18),
              ),
              child: const Icon(Icons.check_rounded, size: 18, color: AppColors.accent),
            ),
            const SizedBox(width: 10),
            const Text(
              '现在可以移开',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChainingBody extends StatelessWidget {
  const _ChainingBody({required this.soundTitle});

  final String soundTitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead(code: 'REGISTERING', title: '声片已封存'),
        const SizedBox(height: 8),
        Text(
          soundTitle.isEmpty
              ? '正在登记数字藏品'
              : '「$soundTitle」正在登记数字藏品',
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            children: [
              _StatusLine(label: '声片写入', value: '已完成', done: true),
              SizedBox(height: 6),
              _StatusLine(label: '本地绑定', value: '已完成', done: true),
              SizedBox(height: 6),
              _StatusLine(label: '数字藏品登记', value: '进行中', done: false),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '无需再次贴近声片',
          style: TextStyle(
            color: AppColors.accent,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.value,
    required this.done,
  });

  final String label;
  final String value;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: done ? AppColors.accent : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
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
        const _SectionHead(code: 'PRESS COMPLETE', title: '封存完成'),
        const SizedBox(height: 8),
        Text(
          chaining
              ? '「$soundTitle」已与实体声片绑定，\n正在生成正式收藏资产。'
              : '声音已加入 Collection',
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
        SecondaryButton(text: '继续写入下一张', onPressed: onContinue),
      ],
    );
  }
}

class _BoundBody extends StatelessWidget {
  const _BoundBody({
    this.title,
    this.timeLabel,
    this.contentId,
    this.onDetectOther,
    this.onViewBoundSound,
  });

  final String? title;
  final String? timeLabel;
  final String? contentId;
  final VoidCallback? onDetectOther;
  final VoidCallback? onViewBoundSound;

  @override
  Widget build(BuildContext context) {
    final shortId = (contentId == null || contentId!.isEmpty)
        ? '—'
        : (contentId!.length <= 10
            ? contentId!
            : '${contentId!.substring(0, 6)}…${contentId!.substring(contentId!.length - 4)}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead(
          code: 'ALREADY BOUND',
          title: '该声片已写入',
        ),
        const SizedBox(height: 8),
        Text(
          title?.isNotEmpty == true ? title! : '已永久写入一段声音',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '写入时间：${timeLabel ?? '—'}',
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
        Text(
          'contentId：$shortId',
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        const Text(
          '每枚声片只能永久写入一次，不提供覆盖写入。\n'
          '云端声音内容已保留，换空白声片后可直接写入，无需重新上传。',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 14),
        PrimaryButton(text: '换空白声片继续写入', onPressed: onDetectOther),
        if (onViewBoundSound != null) ...[
          const SizedBox(height: 8),
          SecondaryButton(text: '查看已绑定声音', onPressed: onViewBoundSound),
        ],
      ],
    );
  }
}

class _FailBody extends StatelessWidget {
  const _FailBody({
    required this.code,
    required this.title,
    required this.message,
    required this.primaryLabel,
    this.onPrimary,
    this.onRetrieve,
    this.note,
  });

  final String code;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onRetrieve;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHead(code: code, title: title),
        const SizedBox(height: 8),
        Text(
          message,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(
            note!,
            style: TextStyle(
              color: AppColors.accent.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 14),
        PrimaryButton(text: primaryLabel, onPressed: onPrimary),
        if (onRetrieve != null) ...[
          const SizedBox(height: 8),
          SecondaryButton(text: '取回声音', onPressed: onRetrieve),
        ],
      ],
    );
  }
}

class _ChainFailBody extends StatelessWidget {
  const _ChainFailBody({
    required this.soundTitle,
    this.failReason,
    this.onRetryChain,
    this.onLater,
    this.onViewCollection,
  });

  final String soundTitle;
  final String? failReason;
  final VoidCallback? onRetryChain;
  final VoidCallback? onLater;
  final VoidCallback? onViewCollection;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead(code: 'CHAIN FAILED', title: '声片已成功写入'),
        const SizedBox(height: 8),
        const Text(
          '数字藏品登记暂时失败',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (failReason != null && failReason!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            failReason!,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
        ],
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '重试只会重新提交登记，不会重新写入 NFC，无需再次贴近声片。',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 14),
        PrimaryButton(text: '重试登记', onPressed: onRetryChain),
        const SizedBox(height: 8),
        SecondaryButton(text: '稍后处理', onPressed: onLater),
        const SizedBox(height: 8),
        SecondaryButton(text: '查看声音', onPressed: onViewCollection),
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
