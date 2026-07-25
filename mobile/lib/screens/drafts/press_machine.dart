import 'dart:math' as math;

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
        PressMachineMode.idle || PressMachineMode.empty => 0.2,
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
        PressMachineMode.idle || PressMachineMode.empty => 0,
        PressMachineMode.receiving => 6,
        PressMachineMode.readyToRelease => 12,
        PressMachineMode.inserting => 8,
        _ => 4,
      };
}

/// 白色陶瓷精密写入机（Widget 组合，避免 CustomPaint 子树撑破导致纯白块）。
class PressMachine extends StatelessWidget {
  const PressMachine({
    super.key,
    required this.mode,
    required this.breath,
    this.guideFlash = 0,
    this.slotKey,
    this.loadedTitle,
    this.maxHeight = 156,
  });

  final PressMachineMode mode;
  final Animation<double> breath;
  final double guideFlash;
  final GlobalKey? slotKey;
  final String? loadedTitle;
  final double maxHeight;

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

        final glow = mode == PressMachineMode.idle
            ? mode.slotGlow * (0.75 + 0.25 * breath.value)
            : mode.slotGlow;

        return LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 320.0;
            final maxH = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : maxHeight;
            final bodyW = math.min(maxW * 0.9, 300.0);
            final bodyH = math.min(maxH - mode.slotExtend - 4, maxHeight)
                .clamp(120.0, maxHeight);

            return Center(
              child: SizedBox(
                width: bodyW,
                height: bodyH + mode.slotExtend + 4,
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        width: bodyW,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(
                            begin: Alignment(-0.7, -1),
                            end: Alignment(0.6, 1),
                            colors: [
                              Color(0xFFFFFFFF),
                              Color(0xFFF2F3F1),
                              Color(0xFFE3E6E3),
                            ],
                          ),
                          border: Border.all(
                            color: AppColors.silver,
                            width: 1.6,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 22,
                              offset: const Offset(0, 12),
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.55),
                              blurRadius: 0,
                              offset: const Offset(0, -0.8),
                              spreadRadius: -0.5,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                        child: Column(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: const Color(0xFFEEF0EE),
                                  border: Border.all(
                                    color: const Color(0xFFC8CEC9),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    _BezelLamps(
                                      mode: mode,
                                      breath: breath.value,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _GlassScreen(
                                        line1: line1,
                                        line2: line2,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    _BezelLamps(
                                      mode: mode,
                                      breath: breath.value,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // 对位标记
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 10,
                                  height: 1.2,
                                  color: AppColors.silverDeep,
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 1.2,
                                  height: 8,
                                  color: AppColors.silverDeep,
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 10,
                                  height: 1.2,
                                  color: AppColors.silverDeep,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 银色插槽（开口朝下）
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      key: slotKey,
                      width: bodyW * 0.58,
                      height: 16 + mode.slotExtend,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFFF4F5F4),
                            Color(0xFFC9CECC),
                            Color(0xFFA8AFA8),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(
                              alpha: 0.15 + 0.35 * glow,
                            ),
                            blurRadius: 8,
                            spreadRadius: glow > 0.5 ? 1 : 0,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(2.5),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: AppColors.slotInterior,
                          border: Border.all(
                            color: Color.lerp(
                              const Color(0xFF3A4240),
                              AppColors.accent,
                              glow * 0.5,
                            )!,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(1),
                            color: AppColors.accent.withValues(
                              alpha: 0.2 + 0.55 * glow,
                            ),
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
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.glassDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2C3432)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      alignment: Alignment.center,
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
              color: AppColors.highlight,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            line2,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Courier',
              fontSize: 9.5,
              color: AppColors.accent,
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
      mainAxisAlignment: MainAxisAlignment.center,
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
                  ? AppColors.accent.withValues(alpha: 0.9 * pulse)
                  : const Color(0xFFD5D9D6),
              border: Border.all(color: AppColors.silverDeep, width: 0.7),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.4 * pulse),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }),
    );
  }
}
