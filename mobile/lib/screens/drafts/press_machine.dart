import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// 拟物化声音写入机器状态（屏幕文案随业务阶段变化，不伪造百分比）。
enum PressMachineMode {
  idle,
  receiving,
  readyToRelease,
  reading,
  verifying,
  binding,
}

extension PressMachineModeX on PressMachineMode {
  (String, String) get screenLines => switch (this) {
        PressMachineMode.idle => ('SOUND PRESS', 'READY'),
        PressMachineMode.receiving => ('INSERT DRAFT', '向上拖入声音'),
        PressMachineMode.readyToRelease => ('RELEASE TO PRESS', '松开开始写入'),
        PressMachineMode.reading => ('READING CHIP', '读取实体声片'),
        PressMachineMode.verifying => ('VERIFYING', '校验绑定状态'),
        PressMachineMode.binding => ('BINDING SOUND', '永久写入中'),
      };

  bool get isActive => this != PressMachineMode.idle;

  bool get isRunning =>
      this == PressMachineMode.reading ||
      this == PressMachineMode.verifying ||
      this == PressMachineMode.binding;

  double get slotGlow {
    return switch (this) {
      PressMachineMode.idle => 0.22,
      PressMachineMode.receiving => 0.55,
      PressMachineMode.readyToRelease => 0.92,
      PressMachineMode.reading ||
      PressMachineMode.verifying ||
      PressMachineMode.binding =>
        0.75,
    };
  }

  /// 插槽向下展开距离（逻辑像素）。
  double get slotExtend {
    return switch (this) {
      PressMachineMode.idle => 0,
      PressMachineMode.receiving => 10,
      PressMachineMode.readyToRelease => 16,
      PressMachineMode.reading ||
      PressMachineMode.verifying ||
      PressMachineMode.binding =>
        6,
    };
  }
}

class PressMachine extends StatelessWidget {
  const PressMachine({
    super.key,
    required this.mode,
    required this.breath,
    this.guideFlash = 0,
    this.slotKey,
  });

  final PressMachineMode mode;
  final Animation<double> breath;
  final double guideFlash;
  final GlobalKey? slotKey;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: breath,
      builder: (context, _) {
        final (line1, line2) = mode.screenLines;
        final glow = mode.slotGlow;
        final breathPulse = 0.7 + 0.3 * breath.value;
        final slotGlow = mode == PressMachineMode.idle
            ? glow * breathPulse
            : glow;

        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final bodyW = math.min(w * 0.88, 340.0);
            final bodyH = math.min(h * 0.92, 220.0);

            return Center(
              child: SizedBox(
                width: bodyW,
                height: bodyH + mode.slotExtend,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned(
                      top: 0,
                      width: bodyW,
                      height: bodyH,
                      child: CustomPaint(
                        painter: _MachineBodyPainter(
                          mode: mode,
                          slotGlow: slotGlow,
                          breath: breath.value,
                          guideFlash: guideFlash,
                        ),
                        child: Stack(
                          children: [
                            // 像素状态屏
                            Positioned(
                              left: bodyW * 0.22,
                              right: bodyW * 0.22,
                              top: bodyH * 0.18,
                              height: bodyH * 0.28,
                              child: _PixelScreen(line1: line1, line2: line2),
                            ),
                            // 状态灯
                            Positioned(
                              left: bodyW * 0.12,
                              top: bodyH * 0.22,
                              child: _StatusLamps(mode: mode, breath: breath.value),
                            ),
                            Positioned(
                              right: bodyW * 0.12,
                              top: bodyH * 0.22,
                              child: _StatusLamps(
                                mode: mode,
                                breath: breath.value,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 底部插槽（开口朝下）
                    Positioned(
                      left: bodyW * 0.18,
                      right: bodyW * 0.18,
                      top: bodyH - 18,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        key: slotKey,
                        height: 22 + mode.slotExtend,
                        child: CustomPaint(
                          painter: _SlotPainter(
                            glow: slotGlow,
                            extend: mode.slotExtend,
                            breath: breath.value,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PixelScreen extends StatelessWidget {
  const _PixelScreen({required this.line1, required this.line2});

  final String line1;
  final String line2;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF061210),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1A2E2A), width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.12),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            line1,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.accent.withValues(alpha: 0.95),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            line2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 9,
              letterSpacing: 0.6,
              color: AppColors.accentSoft.withValues(alpha: 0.75),
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLamps extends StatelessWidget {
  const _StatusLamps({
    required this.mode,
    required this.breath,
  });

  final PressMachineMode mode;
  final double breath;

  @override
  Widget build(BuildContext context) {
    final lit = switch (mode) {
      PressMachineMode.idle => 1,
      PressMachineMode.receiving => 2,
      PressMachineMode.readyToRelease => 3,
      PressMachineMode.reading => 2,
      PressMachineMode.verifying => 3,
      PressMachineMode.binding => 4,
    };

    return Column(
      children: List.generate(4, (i) {
        final on = i < lit;
        final pulse = on && i == lit - 1 ? 0.65 + 0.35 * breath : 1.0;
        return Padding(
          padding: EdgeInsets.only(bottom: i < 3 ? 6 : 0),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on
                  ? AppColors.accent.withValues(alpha: 0.55 * pulse)
                  : const Color(0xFF1A2220),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.35 * pulse),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
              border: Border.all(
                color: const Color(0xFF2A3532),
                width: 1,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _MachineBodyPainter extends CustomPainter {
  _MachineBodyPainter({
    required this.mode,
    required this.slotGlow,
    required this.breath,
    required this.guideFlash,
  });

  final PressMachineMode mode;
  final double slotGlow;
  final double breath;
  final double guideFlash;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(28),
    );

    // 机身主体
    final body = Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width * 0.5, 0),
        Offset(size.width * 0.5, size.height),
        const [
          Color(0xFF1A2220),
          Color(0xFF0C100F),
          Color(0xFF080B0A),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRRect(r, body);

    // 外轮廓高光
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFF3A4844).withValues(alpha: 0.7),
    );
    canvas.drawRRect(
      r.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF151C1A),
    );

    // 内嵌操作面板
    final panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.08,
        size.height * 0.1,
        size.width * 0.84,
        size.height * 0.58,
      ),
      const Radius.circular(16),
    );
    canvas.drawRRect(
      panel,
      Paint()..color = const Color(0xFF050807),
    );
    canvas.drawRRect(
      panel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF1E2A27),
    );

    // 机械刻度条
    final tickY = size.height * 0.78;
    final tickPaint = Paint()
      ..color = const Color(0xFF2A3532)
      ..strokeWidth = 1;
    final accentTick = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.25 + 0.2 * slotGlow)
      ..strokeWidth = 1.2;
    final tickLeft = size.width * 0.16;
    final tickRight = size.width * 0.84;
    final ticks = 17;
    for (var i = 0; i < ticks; i++) {
      final t = i / (ticks - 1);
      final x = ui.lerpDouble(tickLeft, tickRight, t)!;
      final tall = i % 4 == 0;
      canvas.drawLine(
        Offset(x, tickY - (tall ? 7 : 4)),
        Offset(x, tickY + (tall ? 7 : 4)),
        tall ? accentTick : tickPaint,
      );
    }

    // 螺丝
    _drawScrew(canvas, Offset(size.width * 0.1, size.height * 0.12));
    _drawScrew(canvas, Offset(size.width * 0.9, size.height * 0.12));
    _drawScrew(canvas, Offset(size.width * 0.1, size.height * 0.88));
    _drawScrew(canvas, Offset(size.width * 0.9, size.height * 0.88));

    // 拼接缝
    final seam = Paint()
      ..color = const Color(0xFF121816)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.08),
      Offset(size.width * 0.5, size.height * 0.72),
      seam,
    );

    // 引导扫描线（首次引导 / 拖动时）
    if (guideFlash > 0.01 || mode.isActive) {
      final alpha = guideFlash > 0.01
          ? guideFlash
          : (0.15 + 0.25 * slotGlow) * (0.6 + 0.4 * breath);
      final cx = size.width * 0.5;
      final top = size.height * 0.72;
      final bottom = size.height + 8;
      canvas.drawLine(
        Offset(cx, top),
        Offset(cx, bottom),
        Paint()
          ..color = AppColors.accent.withValues(alpha: alpha)
          ..strokeWidth = 1.2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  void _drawScrew(Canvas canvas, Offset c) {
    canvas.drawCircle(c, 4.5, Paint()..color = const Color(0xFF1C2422));
    canvas.drawCircle(
      c,
      4.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF3A4642),
    );
    canvas.drawLine(
      c.translate(-2.2, 0),
      c.translate(2.2, 0),
      Paint()
        ..color = const Color(0xFF2A3532)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      c.translate(0, -2.2),
      c.translate(0, 2.2),
      Paint()
        ..color = const Color(0xFF2A3532)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _MachineBodyPainter old) =>
      old.mode != mode ||
      old.slotGlow != slotGlow ||
      old.breath != breath ||
      old.guideFlash != guideFlash;
}

class _SlotPainter extends CustomPainter {
  _SlotPainter({
    required this.glow,
    required this.extend,
    required this.breath,
  });

  final double glow;
  final double extend;
  final double breath;

  @override
  void paint(Canvas canvas, Size size) {
    final mouth = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(8),
    );

    // 内凹腔体
    canvas.drawRRect(
      mouth,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [
            const Color(0xFF020403),
            Color.lerp(
              const Color(0xFF0A1210),
              AppColors.accent.withValues(alpha: 0.18),
              glow * 0.5,
            )!,
          ],
        ),
    );

    canvas.drawRRect(
      mouth,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Color.lerp(
          const Color(0xFF2A3532),
          AppColors.accent,
          glow * 0.6,
        )!,
    );

    // 扫描光带
    final bandY = size.height * (0.35 + 0.25 * breath);
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.08, bandY - 1.5, size.width * 0.84, 3),
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.25 + 0.45 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // 下缘开口高光
    canvas.drawLine(
      Offset(size.width * 0.12, size.height - 1),
      Offset(size.width * 0.88, size.height - 1),
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.15 + 0.4 * glow)
        ..strokeWidth = 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(covariant _SlotPainter old) =>
      old.glow != glow || old.extend != extend || old.breath != breath;
}
