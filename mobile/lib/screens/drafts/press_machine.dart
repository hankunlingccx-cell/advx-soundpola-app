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
        PressMachineMode.receiving => ('INSERT DRAFT', 'DRAG UP'),
        PressMachineMode.readyToRelease => ('RELEASE TO PRESS', 'CONFIRM'),
        PressMachineMode.reading => ('READING CHIP', 'NFC'),
        PressMachineMode.verifying => ('VERIFYING', 'AUTH'),
        PressMachineMode.binding => ('BINDING SOUND', 'WRITE'),
      };

  bool get isActive => this != PressMachineMode.idle;

  double get slotGlow => switch (this) {
        PressMachineMode.idle => 0.28,
        PressMachineMode.receiving => 0.62,
        PressMachineMode.readyToRelease => 1.0,
        PressMachineMode.reading ||
        PressMachineMode.verifying ||
        PressMachineMode.binding =>
          0.78,
      };

  double get slotExtend => switch (this) {
        PressMachineMode.idle => 0,
        PressMachineMode.receiving => 8,
        PressMachineMode.readyToRelease => 14,
        PressMachineMode.reading ||
        PressMachineMode.verifying ||
        PressMachineMode.binding =>
          4,
      };
}

/// 嵌入黑色工作台的精密声音写入机。
/// 体积靠受光边与内凹层级表现；品牌青仅用于插槽 / 状态灯 / 反馈。
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
        final breathPulse = 0.72 + 0.28 * breath.value;
        final slotGlow = mode == PressMachineMode.idle
            ? mode.slotGlow * breathPulse
            : mode.slotGlow;

        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final bodyW = math.min(w * 0.86, 320.0);
            final bodyH = math.min(h * 0.94, 168.0);

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
                            Positioned(
                              left: bodyW * 0.2,
                              right: bodyW * 0.2,
                              top: bodyH * 0.16,
                              height: bodyH * 0.36,
                              child: _PixelScreen(line1: line1, line2: line2),
                            ),
                            Positioned(
                              left: bodyW * 0.1,
                              top: bodyH * 0.2,
                              child: _StatusLamps(
                                mode: mode,
                                breath: breath.value,
                              ),
                            ),
                            Positioned(
                              right: bodyW * 0.1,
                              top: bodyH * 0.2,
                              child: _StatusLamps(
                                mode: mode,
                                breath: breath.value,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: bodyW * 0.16,
                      right: bodyW * 0.16,
                      top: bodyH - 14,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        key: slotKey,
                        height: 20 + mode.slotExtend,
                        child: CustomPaint(
                          painter: _SlotPainter(
                            glow: slotGlow,
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
        color: const Color(0xFF030605),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.structure.withValues(alpha: 0.9)),
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
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
              color: AppColors.accent.withValues(alpha: 0.92),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            line2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 9,
              letterSpacing: 0.8,
              color: AppColors.textTertiary,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLamps extends StatelessWidget {
  const _StatusLamps({required this.mode, required this.breath});

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
        final pulse = on && i == lit - 1 ? 0.7 + 0.3 * breath : 1.0;
        return Padding(
          padding: EdgeInsets.only(bottom: i < 3 ? 5 : 0),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on
                  ? AppColors.accent.withValues(alpha: 0.7 * pulse)
                  : AppColors.structure,
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.28 * pulse),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
              border: Border.all(
                color: const Color(0xFF3A4441),
                width: 0.8,
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
      const Radius.circular(18),
    );

    // 外壳：深石墨 + 顶部受光
    canvas.drawRRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width * 0.5, 0),
          Offset(size.width * 0.5, size.height),
          const [
            Color(0xFF1C2422),
            Color(0xFF0E1312),
            Color(0xFF080C0B),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );

    // 顶部高光边（非青色）
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height * 0.35),
          [
            const Color(0xFF4A5552).withValues(alpha: 0.85),
            AppColors.structure.withValues(alpha: 0.35),
          ],
        ),
    );

    // 内嵌操作面板（更深凹）
    final panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.07,
        size.height * 0.09,
        size.width * 0.86,
        size.height * 0.55,
      ),
      const Radius.circular(10),
    );
    canvas.drawRRect(panel, Paint()..color = const Color(0xFF040706));
    canvas.drawRRect(
      panel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF1A2220),
    );
    // 面板内缘暗影
    canvas.drawRRect(
      panel.deflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.55),
    );

    // 微型机械刻度（8-bit 克制）
    final tickY = size.height * 0.74;
    final tickLeft = size.width * 0.14;
    final tickRight = size.width * 0.86;
    for (var i = 0; i < 15; i++) {
      final t = i / 14;
      final x = ui.lerpDouble(tickLeft, tickRight, t)!;
      final tall = i % 5 == 0;
      canvas.drawLine(
        Offset(x, tickY - (tall ? 5 : 3)),
        Offset(x, tickY + (tall ? 5 : 3)),
        Paint()
          ..color = tall
              ? AppColors.structure
              : const Color(0xFF1A2220)
          ..strokeWidth = 1,
      );
    }

    _drawScrew(canvas, Offset(size.width * 0.09, size.height * 0.11));
    _drawScrew(canvas, Offset(size.width * 0.91, size.height * 0.11));
    _drawScrew(canvas, Offset(size.width * 0.09, size.height * 0.86));
    _drawScrew(canvas, Offset(size.width * 0.91, size.height * 0.86));

    // 引导扫描线：仅引导 / 拖动时短暂出现
    if (guideFlash > 0.02 || mode.isActive) {
      final alpha = guideFlash > 0.02
          ? guideFlash * 0.55
          : (0.08 + 0.18 * slotGlow);
      final cx = size.width * 0.5;
      canvas.drawLine(
        Offset(cx, size.height * 0.7),
        Offset(cx, size.height + 6),
        Paint()
          ..color = AppColors.accent.withValues(alpha: alpha)
          ..strokeWidth = 1
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }

  void _drawScrew(Canvas canvas, Offset c) {
    canvas.drawCircle(c, 3.8, Paint()..color = const Color(0xFF161C1A));
    canvas.drawCircle(
      c,
      3.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = const Color(0xFF3A4441),
    );
    canvas.drawLine(
      c.translate(-1.8, 0),
      c.translate(1.8, 0),
      Paint()
        ..color = const Color(0xFF2A3532)
        ..strokeWidth = 0.8,
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
  _SlotPainter({required this.glow, required this.breath});

  final double glow;
  final double breath;

  @override
  void paint(Canvas canvas, Size size) {
    final mouth = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );

    // 深凹腔
    canvas.drawRRect(
      mouth,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [
            const Color(0xFF010202),
            Color.lerp(
              const Color(0xFF0A100E),
              AppColors.accent.withValues(alpha: 0.14),
              glow * 0.45,
            )!,
          ],
        ),
    );

    // 结构边（灰），吸附时才带青
    canvas.drawRRect(
      mouth,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = Color.lerp(
          AppColors.structure,
          AppColors.accent,
          glow * 0.55,
        )!,
    );

    // 内口阴影
    canvas.drawRRect(
      mouth.deflate(2.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.65),
    );

    // 低亮度扫描带
    final bandY = size.height * (0.38 + 0.2 * breath);
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.1, bandY - 1, size.width * 0.8, 2),
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.18 + 0.42 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // 下缘开口提示
    canvas.drawLine(
      Offset(size.width * 0.15, size.height - 1),
      Offset(size.width * 0.85, size.height - 1),
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.12 + 0.38 * glow)
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _SlotPainter old) =>
      old.glow != glow || old.breath != breath;
}
