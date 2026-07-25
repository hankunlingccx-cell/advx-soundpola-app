import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// 拟物化声音写入机器状态。
enum PressMachineMode {
  idle,
  receiving,
  readyToRelease,
  inserting,
  loaded,
  found,
  pressing,
  complete,
  interrupted,
  alreadyBound,
  empty,
}

extension PressMachineModeX on PressMachineMode {
  (String, String) get screenLines => switch (this) {
        PressMachineMode.idle => (
            'Ready to Press',
            'Drag a sound card into the slot',
          ),
        PressMachineMode.receiving => ('Insert Sound', 'Move card up'),
        PressMachineMode.readyToRelease => (
            'Release to Insert',
            'Align with the slot',
          ),
        PressMachineMode.inserting => ('Loading…', 'Inserting card'),
        PressMachineMode.loaded => ('Sound Loaded', 'Waiting for piece'),
        PressMachineMode.found => ('Piece Found', 'Hold steady'),
        PressMachineMode.pressing => ('Pressing Sound', 'Do not move'),
        PressMachineMode.complete => ('Press Complete', 'Sound sealed'),
        PressMachineMode.interrupted => ('Interrupted', 'Try again'),
        PressMachineMode.alreadyBound => ('Already Bound', 'Use another piece'),
        PressMachineMode.empty => ('Queue Empty', 'Waiting for sound'),
      };

  bool get isActive =>
      this != PressMachineMode.idle && this != PressMachineMode.empty;

  double get slotGlow => switch (this) {
        PressMachineMode.idle || PressMachineMode.empty => 0.18,
        PressMachineMode.receiving => 0.55,
        PressMachineMode.readyToRelease => 0.95,
        PressMachineMode.inserting => 0.8,
        PressMachineMode.loaded => 0.4,
        PressMachineMode.found => 0.65,
        PressMachineMode.pressing => 0.75,
        PressMachineMode.complete => 0.85,
        PressMachineMode.interrupted || PressMachineMode.alreadyBound => 0.3,
      };

  double get slotExtend => switch (this) {
        PressMachineMode.idle || PressMachineMode.empty => 2,
        PressMachineMode.receiving => 8,
        PressMachineMode.readyToRelease => 14,
        PressMachineMode.inserting => 10,
        PressMachineMode.loaded => 4,
        PressMachineMode.found || PressMachineMode.pressing => 6,
        PressMachineMode.complete => 8,
        PressMachineMode.interrupted || PressMachineMode.alreadyBound => 4,
      };
}

/// 白色陶瓷 × 浅银金属的 iOS 式精密写入机。
class PressMachine extends StatelessWidget {
  const PressMachine({
    super.key,
    required this.mode,
    required this.breath,
    this.guideFlash = 0,
    this.slotKey,
    this.loadedTitle,
  });

  final PressMachineMode mode;
  final Animation<double> breath;
  final double guideFlash;
  final GlobalKey? slotKey;
  final String? loadedTitle;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: breath,
      builder: (context, _) {
        var (line1, line2) = mode.screenLines;
        if ((mode == PressMachineMode.loaded ||
                mode == PressMachineMode.pressing) &&
            loadedTitle != null &&
            loadedTitle!.isNotEmpty) {
          line2 = loadedTitle!;
        }
        final breathPulse = 0.75 + 0.25 * breath.value;
        final slotGlow = mode == PressMachineMode.idle
            ? mode.slotGlow * breathPulse
            : mode.slotGlow;

        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final bodyW = math.min(w * 0.88, 328.0);
            final bodyH = math.min(h * 0.92, 168.0);

            return Center(
              child: SizedBox(
                width: bodyW,
                height: bodyH + mode.slotExtend + 8,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    // 悬浮阴影
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 2,
                      height: 18,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 28,
                              spreadRadius: -4,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      width: bodyW,
                      height: bodyH,
                      child: CustomPaint(
                        painter: _CeramicBodyPainter(
                          mode: mode,
                          slotGlow: slotGlow,
                          breath: breath.value,
                          guideFlash: guideFlash,
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              left: bodyW * 0.18,
                              right: bodyW * 0.18,
                              top: bodyH * 0.16,
                              height: bodyH * 0.38,
                              child: _GlassScreen(line1: line1, line2: line2),
                            ),
                            Positioned(
                              left: bodyW * 0.09,
                              top: bodyH * 0.22,
                              child: _BezelLamps(
                                mode: mode,
                                breath: breath.value,
                              ),
                            ),
                            Positioned(
                              right: bodyW * 0.09,
                              top: bodyH * 0.22,
                              child: _BezelLamps(
                                mode: mode,
                                breath: breath.value,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: bodyW * 0.2,
                      right: bodyW * 0.2,
                      top: bodyH - 12,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        key: slotKey,
                        height: 18 + mode.slotExtend,
                        child: CustomPaint(
                          painter: _SilverSlotPainter(
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

class _GlassScreen extends StatelessWidget {
  const _GlassScreen({required this.line1, required this.line2});

  final String line1;
  final String line2;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3230), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            line1,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Courier',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: AppColors.highlight,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            line2,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 9.5,
              letterSpacing: 0.15,
              color: AppColors.accent.withValues(alpha: 0.92),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _BezelLamps extends StatelessWidget {
  const _BezelLamps({required this.mode, required this.breath});

  final PressMachineMode mode;
  final double breath;

  @override
  Widget build(BuildContext context) {
    final lit = switch (mode) {
      PressMachineMode.idle || PressMachineMode.empty => 1,
      PressMachineMode.receiving => 2,
      PressMachineMode.readyToRelease || PressMachineMode.inserting => 3,
      PressMachineMode.loaded => 2,
      PressMachineMode.found => 3,
      PressMachineMode.pressing || PressMachineMode.complete => 4,
      PressMachineMode.interrupted || PressMachineMode.alreadyBound => 2,
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
                  ? AppColors.accent.withValues(alpha: 0.85 * pulse)
                  : const Color(0xFFD6DAD7),
              border: Border.all(
                color: AppColors.silverDeep.withValues(alpha: 0.7),
                width: 0.8,
              ),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.35 * pulse),
                        blurRadius: 5,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 1,
                        offset: const Offset(0, 0.5),
                      ),
                    ],
            ),
          ),
        );
      }),
    );
  }
}

class _CeramicBodyPainter extends CustomPainter {
  _CeramicBodyPainter({
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
      const Radius.circular(26),
    );

    // 陶瓷白主壳：左上受光
    canvas.drawRRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width * 0.15, 0),
          Offset(size.width * 0.85, size.height),
          const [
            Color(0xFFFFFFFF),
            Color(0xFFF2F3F1),
            Color(0xFFE4E7E4),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );

    // 银色中框环
    canvas.drawRRect(
      r.deflate(1.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [
            AppColors.highlight,
            AppColors.silver,
            AppColors.silverDeep,
          ],
        ),
    );

    // 顶部窄高光
    final highlightPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(10, 3, size.width - 20, size.height * 0.22),
          const Radius.circular(18),
        ),
      );
    canvas.drawPath(
      highlightPath,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, size.height * 0.22),
          [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0),
          ],
        ),
    );

    // 内嵌浅灰白玻璃面板
    final panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.07,
        size.height * 0.09,
        size.width * 0.86,
        size.height * 0.55,
      ),
      const Radius.circular(14),
    );
    canvas.drawRRect(
      panel,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width * 0.5, size.height * 0.09),
          Offset(size.width * 0.5, size.height * 0.64),
          [
            const Color(0xFFF7F8F7).withValues(alpha: 0.95),
            const Color(0xFFE8EBE9).withValues(alpha: 0.9),
          ],
        ),
    );
    // 内凹浅阴影
    canvas.drawRRect(
      panel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFC5CBC8),
    );
    canvas.drawRRect(
      panel.deflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.65),
    );

    // 插槽上方细小对位标记
    final markY = size.height * 0.72;
    final cx = size.width * 0.5;
    final markPaint = Paint()
      ..color = AppColors.silverDeep.withValues(alpha: 0.7)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 18, markY), Offset(cx - 8, markY), markPaint);
    canvas.drawLine(Offset(cx + 8, markY), Offset(cx + 18, markY), markPaint);
    canvas.drawLine(
      Offset(cx, markY - 4),
      Offset(cx, markY + 4),
      markPaint,
    );

    // 极少螺丝（银灰）
    _drawScrew(canvas, Offset(size.width * 0.1, size.height * 0.12));
    _drawScrew(canvas, Offset(size.width * 0.9, size.height * 0.12));

    if (guideFlash > 0.02 || mode.isActive) {
      final alpha = guideFlash > 0.02
          ? guideFlash * 0.4
          : (0.06 + 0.16 * slotGlow);
      canvas.drawLine(
        Offset(cx, size.height * 0.68),
        Offset(cx, size.height + 4),
        Paint()
          ..color = AppColors.accent.withValues(alpha: alpha)
          ..strokeWidth = 1
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      );
    }
  }

  void _drawScrew(Canvas canvas, Offset c) {
    canvas.drawCircle(
      c,
      3.2,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          3.2,
          [AppColors.highlight, AppColors.silver],
        ),
    );
    canvas.drawCircle(
      c,
      3.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = AppColors.silverDeep,
    );
  }

  @override
  bool shouldRepaint(covariant _CeramicBodyPainter old) =>
      old.mode != mode ||
      old.slotGlow != slotGlow ||
      old.breath != breath ||
      old.guideFlash != guideFlash;
}

class _SilverSlotPainter extends CustomPainter {
  _SilverSlotPainter({required this.glow, required this.breath});

  final double glow;
  final double breath;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(7),
    );

    // 银色金属包边
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [
            AppColors.highlight,
            AppColors.silver,
            AppColors.silverDeep,
          ],
        ),
    );

    final inner = outer.deflate(2.2);
    canvas.drawRRect(
      inner,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [
            const Color(0xFF1A1E1C),
            Color.lerp(
              AppColors.slotInterior,
              AppColors.accent.withValues(alpha: 0.2),
              glow * 0.5,
            )!,
          ],
        ),
    );

    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Color.lerp(
          const Color(0xFF3A4240),
          AppColors.accent,
          glow * 0.45,
        )!,
    );

    final bandY = size.height * (0.4 + 0.15 * breath);
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.12, bandY - 1, size.width * 0.76, 2),
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.15 + 0.4 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
  }

  @override
  bool shouldRepaint(covariant _SilverSlotPainter old) =>
      old.glow != glow || old.breath != breath;
}
