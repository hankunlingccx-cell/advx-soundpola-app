import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/disc_rarity.dart';
import '../theme/app_colors.dart';

/// 声片稀有度镭射视觉规范：等级越高，光谱越宽、扫光越绚烂，并叠加差异化外围反馈。
///
/// 分级原则（与贴图解耦，全站统一）：
/// - N：银灰薄荷单色弱镭射，缓慢安静
/// - R：薄荷青主色 + 轻微冷蓝折射
/// - SR：青→蓝→紫三色棱镜，双扫光带
/// - SSR：青→蓝→紫→粉全光谱，多带棱镜 + 独占微粒／视差／揭晓爆发
class RarityHoloStyle {
  const RarityHoloStyle({
    required this.rarity,
    required this.spectrum,
    required this.accent,
    required this.secondaryAccent,
    required this.intensity,
    required this.bandStrength,
    required this.sweepSeconds,
    required this.bandCount,
    required this.rimWidth,
    required this.glowAlpha,
    required this.hasSecondaryRim,
    required this.hasOuterPrism,
  });

  final DiscRarity rarity;
  final List<Color> spectrum;
  final Color accent;
  final Color secondaryAccent;
  final double intensity;
  final double bandStrength;
  final double sweepSeconds;
  final int bandCount;
  final double rimWidth;
  final double glowAlpha;
  final bool hasSecondaryRim;
  final bool hasOuterPrism;

  static const _silver = Color(0xFFC8D4D0);
  static const _mint = Color(0xFF4DFFD6);
  static const _blue = Color(0xFF3DB8FF);
  static const _violet = Color(0xFF9B6BFF);
  static const _pink = Color(0xFFFF5CA8);
  static const _goldHint = Color(0xFFFFE08A);

  static RarityHoloStyle of(DiscRarity? rarity) {
    final r = rarity ?? DiscRarity.n;
    return switch (r) {
      DiscRarity.n => const RarityHoloStyle(
          rarity: DiscRarity.n,
          spectrum: [_silver, _mint, _silver],
          accent: _silver,
          secondaryAccent: _mint,
          intensity: 1.1,
          bandStrength: 0.9,
          sweepSeconds: 5.0,
          bandCount: 1,
          rimWidth: 1.2,
          glowAlpha: 0.26,
          hasSecondaryRim: false,
          hasOuterPrism: false,
        ),
      DiscRarity.r => const RarityHoloStyle(
          rarity: DiscRarity.r,
          spectrum: [_mint, Color(0xFF7AEFDD), _blue, _mint],
          accent: _mint,
          secondaryAccent: _blue,
          intensity: 1.25,
          bandStrength: 1.05,
          sweepSeconds: 3.8,
          bandCount: 2,
          rimWidth: 1.4,
          glowAlpha: 0.36,
          hasSecondaryRim: false,
          hasOuterPrism: false,
        ),
      DiscRarity.sr => const RarityHoloStyle(
          rarity: DiscRarity.sr,
          spectrum: [_mint, _blue, _violet, _blue, _mint],
          accent: _blue,
          secondaryAccent: _violet,
          intensity: 1.4,
          bandStrength: 1.15,
          sweepSeconds: 3.0,
          bandCount: 2,
          rimWidth: 1.6,
          glowAlpha: 0.46,
          hasSecondaryRim: true,
          hasOuterPrism: true,
        ),
      DiscRarity.ssr => const RarityHoloStyle(
          rarity: DiscRarity.ssr,
          spectrum: [_mint, _blue, _violet, _pink, _goldHint, _mint],
          accent: _pink,
          secondaryAccent: _violet,
          intensity: 1.55,
          bandStrength: 1.25,
          sweepSeconds: 2.4,
          bandCount: 3,
          rimWidth: 1.85,
          glowAlpha: 0.55,
          hasSecondaryRim: true,
          hasOuterPrism: true,
        ),
    };
  }

  /// Chip / 文案用色板（bg, fg）。
  (Color, Color) get chipPalette => switch (rarity) {
        DiscRarity.n => (AppColors.surface2, AppColors.textSecondary),
        DiscRarity.r => (
            _mint.withValues(alpha: 0.12),
            _mint,
          ),
        DiscRarity.sr => (
            _blue.withValues(alpha: 0.16),
            _blue,
          ),
        DiscRarity.ssr => (
            _pink.withValues(alpha: 0.18),
            _pink,
          ),
      };
}

/// 卡面镭射扫光层：左上→右下对角平移（非旋转）。
/// 只在移动的高光带上叠镭射色散，不给整圆片铺色。
class RarityHoloSheenPainter extends CustomPainter {
  RarityHoloSheenPainter({
    required this.t,
    required this.style,
    this.intensityScale = 1.0,
  });

  final double t;
  final RarityHoloStyle style;
  final double intensityScale;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    final strength = (style.intensity * intensityScale).clamp(0.7, 1.5);
    final travel = t;

    // 仅扫光带：彩色色散在两侧，白高光芯居中（不铺整面）
    for (var i = 0; i < style.bandCount; i++) {
      final hueA = style.spectrum[i % style.spectrum.length];
      final hueB = style.spectrum[(i + 1) % style.spectrum.length];
      final lag = i / math.max(1, style.bandCount);
      final u = (travel + lag * 0.26) % 1.0;
      final mid = -1.4 + u * 2.8;
      final halfW = 0.26 + i * 0.04;
      // 色散要够显：srcOver 直接上色，不受浅底洗掉
      final tint = (style.bandStrength * strength * 0.85).clamp(0.55, 0.95);
      final sheen = (0.1 + 0.08 * strength).clamp(0.1, 0.22);

      // 1) 彩色扫带（主可见层）— 只在窄带内
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.srcOver
          ..shader = LinearGradient(
            begin: Alignment(mid - halfW, mid - halfW),
            end: Alignment(mid + halfW, mid + halfW),
            colors: [
              Colors.transparent,
              hueA.withValues(alpha: tint * 0.7),
              hueA.withValues(alpha: tint),
              hueB.withValues(alpha: tint),
              hueB.withValues(alpha: tint * 0.7),
              Colors.transparent,
            ],
            stops: const [0.0, 0.18, 0.38, 0.62, 0.82, 1.0],
          ).createShader(rect),
      );

      // 2) screen 再提亮色散，贴图深浅都能看清
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.screen
          ..shader = LinearGradient(
            begin: Alignment(mid - halfW * 1.1, mid - halfW * 1.1),
            end: Alignment(mid + halfW * 1.1, mid + halfW * 1.1),
            colors: [
              Colors.transparent,
              hueA.withValues(alpha: tint * 0.85),
              hueB.withValues(alpha: tint * 0.95),
              Colors.transparent,
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ).createShader(rect),
      );

      // 3) 窄白高光芯 — 叠在色带中央，像箔片反光（压低以免冲掉色）
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.softLight
          ..shader = LinearGradient(
            begin: Alignment(mid - halfW * 0.32, mid - halfW * 0.32),
            end: Alignment(mid + halfW * 0.32, mid + halfW * 0.32),
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: sheen * 0.45),
              Colors.white.withValues(alpha: sheen),
              Colors.white.withValues(alpha: sheen * 0.45),
              Colors.transparent,
            ],
            stops: const [0.0, 0.32, 0.5, 0.68, 1.0],
          ).createShader(rect),
      );

      // 4) R+：plus 棱镜芯，色更跳
      if (style.rarity.index >= DiscRarity.r.index) {
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = LinearGradient(
              begin: Alignment(mid - halfW * 0.75, mid - halfW * 0.75),
              end: Alignment(mid + halfW * 0.75, mid + halfW * 0.75),
              colors: [
                Colors.transparent,
                hueA.withValues(alpha: tint * 0.65),
                hueB.withValues(alpha: tint * 0.75),
                Colors.transparent,
              ],
              stops: const [0.0, 0.32, 0.68, 1.0],
            ).createShader(rect),
        );
      }
    }

    // SR+：外缘扫光掠过时亮一截色散，不做整环染色
    if (style.hasOuterPrism) {
      final rimTravel = (travel * 0.92) % 1.0;
      final rimMid = -1.2 + rimTravel * 2.4;
      final hue = style.accent;
      final hue2 = style.secondaryAccent;
      final rimA = (0.55 + 0.35 * strength).clamp(0.5, 0.95);
      canvas.drawCircle(
        c,
        r * 0.93,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * (style.rarity == DiscRarity.ssr ? 0.08 : 0.055)
          ..blendMode = BlendMode.srcOver
          ..shader = LinearGradient(
            begin: Alignment(rimMid - 0.5, rimMid - 0.5),
            end: Alignment(rimMid + 0.5, rimMid + 0.5),
            colors: [
              Colors.transparent,
              hue.withValues(alpha: rimA * 0.75),
              Colors.white.withValues(alpha: rimA * 0.35),
              hue2.withValues(alpha: rimA),
              Colors.transparent,
            ],
            stops: const [0.0, 0.28, 0.5, 0.72, 1.0],
          ).createShader(rect)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            style.rarity == DiscRarity.ssr ? 1.4 : 0.9,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant RarityHoloSheenPainter old) =>
      old.t != t ||
      old.style.rarity != style.rarity ||
      old.intensityScale != intensityScale;
}

/// 可直接叠在圆形声片上的动画镭射层（按稀有度调节光谱与速度）。
class RarityHoloOverlay extends StatefulWidget {
  const RarityHoloOverlay({
    super.key,
    required this.rarity,
    this.intensityScale = 1.0,
    this.enabled = true,
  });

  final DiscRarity? rarity;
  final double intensityScale;
  final bool enabled;

  @override
  State<RarityHoloOverlay> createState() => _RarityHoloOverlayState();
}

class _RarityHoloOverlayState extends State<RarityHoloOverlay>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  RarityHoloStyle get _style => RarityHoloStyle.of(widget.rarity);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant RarityHoloOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rarity != widget.rarity ||
        oldWidget.enabled != widget.enabled) {
      _sync();
    }
  }

  void _sync() {
    if (!widget.enabled) {
      _ctrl?.stop();
      return;
    }
    final ms = (_style.sweepSeconds * 1000).round();
    if (_ctrl == null) {
      _ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: ms),
      )..repeat();
    } else {
      _ctrl!.duration = Duration(milliseconds: ms);
      if (!_ctrl!.isAnimating) _ctrl!.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _ctrl == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _ctrl!,
      builder: (context, _) {
        return CustomPaint(
          painter: RarityHoloSheenPainter(
            t: _ctrl!.value,
            style: _style,
            intensityScale: widget.intensityScale,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

/// 静态圆形镭射叠层：仅高光扫带色散，不铺整面色。
void paintRarityHoloOverlay({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required DiscRarity? rarity,
  required double elevatedBoost,
  double phase = 0.15,
}) {
  final style = RarityHoloStyle.of(rarity);
  final strength =
      (style.intensity * (0.75 + 0.4 * elevatedBoost)).clamp(0.7, 1.4);
  final rect = Rect.fromCircle(center: center, radius: radius);
  final mid = -1.15 + phase.clamp(0.0, 1.0) * 2.3;
  final halfW = 0.22;
  final tint = (style.bandStrength * strength * 0.85).clamp(0.55, 0.95);
  final sheen = (0.1 + 0.08 * strength).clamp(0.1, 0.22);

  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = LinearGradient(
        begin: Alignment(mid - halfW, mid - halfW),
        end: Alignment(mid + halfW, mid + halfW),
        colors: [
          Colors.transparent,
          style.accent.withValues(alpha: tint * 0.75),
          style.accent.withValues(alpha: tint),
          style.secondaryAccent.withValues(alpha: tint),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.42, 0.72, 1.0],
      ).createShader(rect),
  );

  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..blendMode = BlendMode.screen
      ..shader = LinearGradient(
        begin: Alignment(mid - halfW * 1.05, mid - halfW * 1.05),
        end: Alignment(mid + halfW * 1.05, mid + halfW * 1.05),
        colors: [
          Colors.transparent,
          style.accent.withValues(alpha: tint * 0.8),
          style.secondaryAccent.withValues(alpha: tint * 0.9),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(rect),
  );

  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..blendMode = BlendMode.softLight
      ..shader = LinearGradient(
        begin: Alignment(mid - halfW * 0.32, mid - halfW * 0.32),
        end: Alignment(mid + halfW * 0.32, mid + halfW * 0.32),
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: sheen),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect),
  );
}

/// 等级描边色：主 rim + 可选次 rim。
(Color, Color?) rarityRimColors(DiscRarity? rarity, {required bool elevated}) {
  final s = RarityHoloStyle.of(rarity);
  final main = s.accent.withValues(alpha: elevated ? 0.95 : 0.65);
  final second = s.hasSecondaryRim
      ? s.secondaryAccent.withValues(alpha: elevated ? 0.55 : 0.35)
      : null;
  return (main, second);
}
