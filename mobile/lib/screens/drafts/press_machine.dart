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
            'READY TO PRESS',
            'SELECT A SOUND CARD',
          ),
        PressMachineMode.receiving => ('INSERT SOUND', 'DRAG UP TO SLOT'),
        PressMachineMode.readyToRelease => (
            'RELEASE TO INSERT',
            'ALIGN WITH SLOT',
          ),
        PressMachineMode.inserting => ('LOADING…', 'INSERTING CARD'),
        PressMachineMode.loaded => ('SOUND LOADED', 'WAITING FOR PIECE'),
        PressMachineMode.found => ('PIECE FOUND', 'HOLD STEADY'),
        PressMachineMode.pressing => ('PRESSING SOUND', 'DO NOT MOVE'),
        PressMachineMode.complete => ('PRESS COMPLETE', 'SOUND SEALED'),
        PressMachineMode.interrupted => ('INTERRUPTED', 'TRY AGAIN'),
        PressMachineMode.alreadyBound => ('ALREADY BOUND', 'USE ANOTHER PIECE'),
        PressMachineMode.empty => ('QUEUE EMPTY', 'RECORD A SOUND'),
      };

  bool get isActive =>
      this != PressMachineMode.idle && this != PressMachineMode.empty;

  double get slotGlow => switch (this) {
        PressMachineMode.idle || PressMachineMode.empty => 0.22,
        PressMachineMode.receiving => 0.62,
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
        PressMachineMode.receiving => 7,
        PressMachineMode.readyToRelease => 13,
        PressMachineMode.inserting => 9,
        _ => 4,
      };
}

/// Ceramic desktop press — layered shell, glass screen, deep slot.
class PressMachine extends StatelessWidget {
  const PressMachine({
    super.key,
    required this.mode,
    required this.breath,
    this.guideFlash = 0,
    this.slotKey,
    this.loadedTitle,
    this.maxHeight = 168,
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
          line2 = loadedTitle!.toUpperCase();
        }

        final glow = mode == PressMachineMode.idle
            ? mode.slotGlow * (0.72 + 0.28 * breath.value)
            : mode.slotGlow;

        return LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 320.0;
            final maxH = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : maxHeight;
            final bodyW = math.min(maxW * 0.92, 312.0);
            final bodyH = math.min(maxH - mode.slotExtend - 6, maxHeight)
                .clamp(128.0, maxHeight);

            return Center(
              child: SizedBox(
                width: bodyW + 8,
                height: bodyH + mode.slotExtend + 18,
                child: Stack(
                  alignment: Alignment.topCenter,
                  clipBehavior: Clip.none,
                  children: [
                    // Soft elliptical contact shadow
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 2,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 18,
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        // Outer shell layer
                        Expanded(
                          child: Container(
                            width: bodyW,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(26),
                              gradient: const LinearGradient(
                                begin: Alignment(-0.75, -1),
                                end: Alignment(0.55, 1.1),
                                colors: [
                                  Color(0xFFFFFFFF),
                                  Color(0xFFF4F4F1),
                                  Color(0xFFE6E8E4),
                                ],
                              ),
                              border: Border.all(
                                color: const Color(0xFFC9CECC),
                                width: 1.4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.38),
                                  blurRadius: 24,
                                  offset: const Offset(0, 14),
                                ),
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  blurRadius: 0,
                                  offset: const Offset(0, -1),
                                  spreadRadius: -0.5,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.fromLTRB(11, 11, 11, 9),
                            child: Container(
                              // Mid bezel / recessed panel
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFF0F1EF),
                                    Color(0xFFE4E7E4),
                                  ],
                                ),
                                border: Border.all(
                                  color: const Color(0xFFBFC5C1),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                    spreadRadius: -1,
                                  ),
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    blurRadius: 0,
                                    offset: const Offset(0, 1),
                                    spreadRadius: -2,
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        _BezelLamps(
                                          mode: mode,
                                          breath: breath.value,
                                        ),
                                        const SizedBox(width: 9),
                                        Expanded(
                                          child: _GlassScreen(
                                            line1: line1,
                                            line2: line2,
                                          ),
                                        ),
                                        const SizedBox(width: 9),
                                        _BezelLamps(
                                          mode: mode,
                                          breath: breath.value,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  // Alignment ticks
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 11,
                                        height: 1.2,
                                        color: AppColors.silverDeep
                                            .withValues(alpha: 0.7),
                                      ),
                                      const SizedBox(width: 5),
                                      Container(
                                        width: 1.2,
                                        height: 7,
                                        color: AppColors.silverDeep
                                            .withValues(alpha: 0.7),
                                      ),
                                      const SizedBox(width: 5),
                                      Container(
                                        width: 11,
                                        height: 1.2,
                                        color: AppColors.silverDeep
                                            .withValues(alpha: 0.7),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Deep horizontal slot
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          key: slotKey,
                          width: bodyW * 0.56,
                          height: 18 + mode.slotExtend,
                          margin: const EdgeInsets.only(top: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(7),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFFF6F7F5),
                                Color(0xFFC9CECC),
                                Color(0xFF9AA19C),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withValues(
                                  alpha: 0.12 + 0.4 * glow,
                                ),
                                blurRadius: 10,
                                spreadRadius: glow > 0.55 ? 1 : 0,
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.fromLTRB(3, 3.5, 3, 3),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4.5),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFF1A1E1C),
                                  Color(0xFF2A322F),
                                  Color(0xFF181C1A),
                                ],
                              ),
                              border: Border.all(
                                color: Color.lerp(
                                  const Color(0xFF3A4240),
                                  AppColors.accent,
                                  glow * 0.55,
                                )!,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                  spreadRadius: -1,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Container(
                              height: 2.2,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(1),
                                color: AppColors.accent.withValues(
                                  alpha: 0.18 + 0.62 * glow,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.accent.withValues(
                                      alpha: 0.25 * glow,
                                    ),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
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
        color: const Color(0xFF0B0E0D),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF2A322F)),
        boxShadow: [
          // Inset-like recess
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 8,
            offset: const Offset(0, 3),
            spreadRadius: -1,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.06),
            blurRadius: 0,
            offset: const Offset(0, 1),
            spreadRadius: -2,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            line1,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.highlight.withValues(alpha: 0.92),
              height: 1.15,
              letterSpacing: 0.8,
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
              fontSize: 9,
              color: AppColors.accent.withValues(alpha: 0.92),
              height: 1.2,
              letterSpacing: 0.4,
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
        final pulse = on && i == lit - 1 ? 0.65 + 0.35 * breath : 1.0;
        return Padding(
          padding: EdgeInsets.only(bottom: i < 3 ? 5 : 0),
          child: Container(
            width: 6.5,
            height: 6.5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on
                  ? AppColors.accent.withValues(alpha: 0.92 * pulse)
                  : const Color(0xFFD0D4D1),
              border: Border.all(color: AppColors.silverDeep, width: 0.7),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.45 * pulse),
                        blurRadius: 5,
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
