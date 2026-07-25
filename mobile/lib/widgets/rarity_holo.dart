import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/disc_rarity.dart';
import '../theme/app_colors.dart';

/// 声片稀有度全息箔片视觉：逼真镭射（虹彩底 + 衍射光栅 + 色散高光 + 微闪）。
///
/// 分级：
/// - N：银灰冷箔，慢扫、弱虹彩
/// - R：薄荷青主箔 + 冷蓝折射
/// - SR：青→蓝→紫棱镜箔，双高光／边缘焦散
/// - SSR：全光谱箔 + 密集微闪 + 强边缘焦散
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
    required this.glitterCount,
    required this.gratingDensity,
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
  final int glitterCount;
  final double gratingDensity;

  static const _silver = Color(0xFFE8EEF0);
  static const _mint = Color(0xFF63E0CB);
  static const _cyan = Color(0xFF3DE8FF);
  static const _blue = Color(0xFF4B9FFF);
  static const _violet = Color(0xFF9B6BFF);
  static const _magenta = Color(0xFFFF4DC8);
  static const _pink = Color(0xFFFF7AB8);
  static const _gold = Color(0xFFFFD56A);

  /// 逼真全息虹彩（冷→暖循环）。
  static const rainbow = [
    Color(0xFF63E0CB),
    Color(0xFF3DE8FF),
    Color(0xFF4B9FFF),
    Color(0xFF9B6BFF),
    Color(0xFFFF4DC8),
    Color(0xFFFF7AB8),
    Color(0xFFFFD56A),
    Color(0xFF63E0CB),
  ];

  static RarityHoloStyle of(DiscRarity? rarity) {
    final r = rarity ?? DiscRarity.n;
    return switch (r) {
      DiscRarity.n => const RarityHoloStyle(
          rarity: DiscRarity.n,
          spectrum: [_silver, _mint, _silver, Color(0xFFB8D4E8)],
          accent: _silver,
          secondaryAccent: _mint,
          intensity: 0.85,
          bandStrength: 0.7,
          sweepSeconds: 6.5,
          bandCount: 1,
          rimWidth: 1.2,
          glowAlpha: 0.22,
          hasSecondaryRim: false,
          hasOuterPrism: false,
          glitterCount: 0,
          gratingDensity: 7,
        ),
      DiscRarity.r => const RarityHoloStyle(
          rarity: DiscRarity.r,
          spectrum: [_mint, _cyan, _blue, _mint],
          accent: _mint,
          secondaryAccent: _blue,
          intensity: 1.05,
          bandStrength: 0.9,
          sweepSeconds: 4.8,
          bandCount: 2,
          rimWidth: 1.4,
          glowAlpha: 0.34,
          hasSecondaryRim: false,
          hasOuterPrism: false,
          glitterCount: 10,
          gratingDensity: 10,
        ),
      DiscRarity.sr => const RarityHoloStyle(
          rarity: DiscRarity.sr,
          spectrum: [_mint, _cyan, _blue, _violet, _cyan],
          accent: _blue,
          secondaryAccent: _violet,
          intensity: 1.2,
          bandStrength: 1.05,
          sweepSeconds: 3.6,
          bandCount: 2,
          rimWidth: 1.65,
          glowAlpha: 0.44,
          hasSecondaryRim: true,
          hasOuterPrism: true,
          glitterCount: 22,
          gratingDensity: 14,
        ),
      DiscRarity.ssr => const RarityHoloStyle(
          rarity: DiscRarity.ssr,
          spectrum: rainbow,
          accent: _magenta,
          secondaryAccent: _gold,
          intensity: 1.35,
          bandStrength: 1.2,
          sweepSeconds: 2.8,
          bandCount: 3,
          rimWidth: 1.9,
          glowAlpha: 0.55,
          hasSecondaryRim: true,
          hasOuterPrism: true,
          glitterCount: 42,
          gratingDensity: 18,
        ),
    };
  }

  (Color, Color) get chipPalette => switch (rarity) {
        DiscRarity.n => (AppColors.surface2, AppColors.textSecondary),
        DiscRarity.r => (_mint.withValues(alpha: 0.12), _mint),
        DiscRarity.sr => (_blue.withValues(alpha: 0.16), _blue),
        DiscRarity.ssr => (_magenta.withValues(alpha: 0.18), _pink),
      };
}

/// 逼真全息箔片：虹彩底膜 → 衍射光栅 → RGB 色散高光 → 微闪 → 边缘焦散。
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
    final strength = (style.intensity * intensityScale).clamp(0.55, 1.6);
    final phase = t;

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));

    _paintIridescentBase(canvas, rect, c, r, phase, strength);
    _paintDiffractionGrating(canvas, rect, c, r, phase, strength);
    for (var i = 0; i < style.bandCount; i++) {
      _paintSpecularBeam(canvas, rect, c, r, phase, strength, i);
    }
    if (style.glitterCount > 0) {
      _paintGlitter(canvas, c, r, phase, strength);
    }
    if (style.hasOuterPrism) {
      _paintRimCaustic(canvas, rect, c, r, phase, strength);
    }

    canvas.restore();
  }

  /// 全息底膜：随相位缓慢旋转的虹彩，softLight 贴在卡面上。
  void _paintIridescentBase(
    Canvas canvas,
    Rect rect,
    Offset c,
    double r,
    double phase,
    double strength,
  ) {
    final a = (0.18 + 0.14 * strength * style.bandStrength).clamp(0.12, 0.42);
    final colors = <Color>[];
    final stops = <double>[];
    final n = style.spectrum.length;
    for (var i = 0; i < n; i++) {
      final hue = style.spectrum[i];
      colors.add(hue.withValues(alpha: a * (i.isEven ? 0.85 : 1.0)));
      stops.add(i / n);
    }
    colors.add(style.spectrum.first.withValues(alpha: a * 0.85));
    stops.add(1.0);

    final angle = phase * math.pi * 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.softLight
        ..shader = SweepGradient(
          startAngle: angle,
          endAngle: angle + math.pi * 2,
          colors: colors,
          stops: stops,
          transform: GradientRotation(angle * 0.35),
        ).createShader(rect),
    );

    // 第二层略偏色相，模拟多层箔膜干涉
    final a2 = a * 0.55;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.overlay
        ..shader = SweepGradient(
          startAngle: -angle * 0.7,
          endAngle: -angle * 0.7 + math.pi * 2,
          colors: [
            style.accent.withValues(alpha: a2),
            style.secondaryAccent.withValues(alpha: a2 * 0.9),
            Colors.white.withValues(alpha: a2 * 0.35),
            style.spectrum[(style.spectrum.length ~/ 2) % style.spectrum.length]
                .withValues(alpha: a2),
            style.accent.withValues(alpha: a2),
          ],
        ).createShader(rect),
    );
  }

  /// 衍射光栅：细密斜向彩虹条纹滚动，像压纹箔。
  void _paintDiffractionGrating(
    Canvas canvas,
    Rect rect,
    Offset c,
    double r,
    double phase,
    double strength,
  ) {
    final density = style.gratingDensity;
    final scroll = (phase * 1.35) % 1.0;
    final tint = (0.1 + 0.12 * strength * style.bandStrength).clamp(0.08, 0.28);

    // 主光栅（~28°）
    _drawGratingPass(
      canvas,
      rect,
      c,
      r,
      angleDeg: 28,
      density: density,
      scroll: scroll,
      tint: tint,
      blend: BlendMode.screen,
    );

    // 交叉光栅（~-18°），更稀、更淡 → 产生干涉网纹感
    if (style.rarity.index >= DiscRarity.r.index) {
      _drawGratingPass(
        canvas,
        rect,
        c,
        r,
        angleDeg: -18,
        density: density * 0.65,
        scroll: (scroll * 0.7 + 0.2) % 1.0,
        tint: tint * 0.7,
        blend: BlendMode.plus,
      );
    }
  }

  void _drawGratingPass(
    Canvas canvas,
    Rect rect,
    Offset c,
    double r, {
    required double angleDeg,
    required double density,
    required double scroll,
    required double tint,
    required BlendMode blend,
  }) {
    final spectrum = style.spectrum;
    final bands = math.max(5, density.round());
    // 每条光栅：透明 → 彩虹峰 → 透明，形成细密压纹
    final colors = <Color>[];
    final stops = <double>[];
    for (var i = 0; i < bands; i++) {
      final u0 = i / bands;
      final u1 = (i + 0.45) / bands;
      final u2 = (i + 1) / bands;
      final hue = spectrum[(i + (scroll * 11).floor()) % spectrum.length];
      final peak = tint * (0.55 + 0.45 * math.sin((i + scroll * bands) * 0.9).abs());
      colors.addAll([
        Colors.transparent,
        hue.withValues(alpha: peak),
        Colors.transparent,
      ]);
      stops.addAll([u0, u1.clamp(u0 + 0.001, u2 - 0.001), u2]);
    }

    final rad = angleDeg * math.pi / 180;
    final dx = math.cos(rad);
    final dy = math.sin(rad);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = blend
        ..shader = LinearGradient(
          begin: Alignment(-dx, -dy),
          end: Alignment(dx, dy),
          colors: colors,
          stops: stops,
        ).createShader(rect),
    );
  }

  /// 主高光束：白芯 + RGB 色散边（真实箔片扫光感）。
  void _paintSpecularBeam(
    Canvas canvas,
    Rect rect,
    Offset c,
    double r,
    double phase,
    double strength,
    int index,
  ) {
    final lag = index / math.max(1, style.bandCount);
    final u = (phase * (1.0 + index * 0.12) + lag * 0.33) % 1.0;
    // ease：两端慢、中间快一点更像光照掠过
    final eased = Curves.easeInOutCubic.transform(u);
    final mid = -1.35 + eased * 2.7;
    final halfW = 0.18 + index * 0.04;
    final beamA = (0.35 + 0.35 * strength * style.bandStrength).clamp(0.28, 0.9);

    // 色散：R / G / B 略错开
    final fringe = 0.045 + index * 0.01;
    final hueA = style.spectrum[index % style.spectrum.length];
    final hueB = style.spectrum[(index + 2) % style.spectrum.length];

    void beam(Color color, double offset, double alpha, BlendMode mode) {
      final m = mid + offset;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = mode
          ..shader = LinearGradient(
            begin: Alignment(m - halfW, m - halfW),
            end: Alignment(m + halfW, m + halfW),
            colors: [
              Colors.transparent,
              color.withValues(alpha: alpha * 0.35),
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * 0.35),
              Colors.transparent,
            ],
            stops: const [0.0, 0.28, 0.5, 0.72, 1.0],
          ).createShader(rect),
      );
    }

    beam(const Color(0xFFFF6B6B), -fringe, beamA * 0.55, BlendMode.screen);
    beam(const Color(0xFF6BFFB8), 0, beamA * 0.4, BlendMode.screen);
    beam(const Color(0xFF6BA8FF), fringe, beamA * 0.55, BlendMode.screen);
    beam(hueA, -fringe * 0.5, beamA * 0.65, BlendMode.plus);
    beam(hueB, fringe * 0.5, beamA * 0.65, BlendMode.plus);

    // 白镜面芯
    final sheen = (0.22 + 0.2 * strength).clamp(0.18, 0.55);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.softLight
        ..shader = LinearGradient(
          begin: Alignment(mid - halfW * 0.38, mid - halfW * 0.38),
          end: Alignment(mid + halfW * 0.38, mid + halfW * 0.38),
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: sheen * 0.45),
            Colors.white.withValues(alpha: sheen),
            Colors.white.withValues(alpha: sheen * 0.45),
            Colors.transparent,
          ],
          stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
        ).createShader(rect),
    );

    // 更窄的硬高光
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          begin: Alignment(mid - halfW * 0.12, mid - halfW * 0.12),
          end: Alignment(mid + halfW * 0.12, mid + halfW * 0.12),
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: sheen * 0.85),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect),
    );
  }

  /// 确定性微闪：相位掠过时局部爆亮。
  void _paintGlitter(
    Canvas canvas,
    Offset c,
    double r,
    double phase,
    double strength,
  ) {
    final rng = math.Random(style.rarity.index * 9973 + 41);
    final count = style.glitterCount;
    for (var i = 0; i < count; i++) {
      final ang = rng.nextDouble() * math.pi * 2;
      final rad = math.sqrt(rng.nextDouble()) * r * 0.92;
      final p = Offset(c.dx + math.cos(ang) * rad, c.dy + math.sin(ang) * rad);
      final sparkPhase = (phase * 2.4 + rng.nextDouble()) % 1.0;
      // 窄脉冲：只有一小段相位亮
      final pulse = math
          .pow(math.max(0.0, 1.0 - ((sparkPhase - 0.5).abs() * 8.0)), 2)
          .toDouble();
      if (pulse < 0.05) continue;

      final hue = style.spectrum[i % style.spectrum.length];
      final sz = (0.6 + rng.nextDouble() * 1.8) * (0.85 + 0.3 * strength);
      final a = (pulse * 0.55 * strength).clamp(0.0, 0.85);

      canvas.drawCircle(
        p,
        sz,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = hue.withValues(alpha: a),
      );
      if (pulse > 0.55) {
        canvas.drawCircle(
          p,
          sz * 0.35,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = Colors.white.withValues(alpha: a * 0.9),
        );
      }
    }
  }

  /// 边缘菲涅尔焦散：扫光掠过时外缘亮一截彩虹。
  void _paintRimCaustic(
    Canvas canvas,
    Rect rect,
    Offset c,
    double r,
    double phase,
    double strength,
  ) {
    final rimTravel = (phase * 0.95) % 1.0;
    final rimMid = -1.25 + rimTravel * 2.5;
    final rimA = (0.4 + 0.35 * strength).clamp(0.35, 0.9);
    final w = r * (style.rarity == DiscRarity.ssr ? 0.07 : 0.05);

    canvas.drawCircle(
      c,
      r * 0.965,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..blendMode = BlendMode.screen
        ..shader = LinearGradient(
          begin: Alignment(rimMid - 0.55, rimMid - 0.55),
          end: Alignment(rimMid + 0.55, rimMid + 0.55),
          colors: [
            Colors.transparent,
            style.accent.withValues(alpha: rimA * 0.7),
            Colors.white.withValues(alpha: rimA * 0.55),
            style.secondaryAccent.withValues(alpha: rimA),
            Colors.transparent,
          ],
          stops: const [0.0, 0.28, 0.5, 0.72, 1.0],
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );

    if (style.rarity == DiscRarity.ssr) {
      canvas.drawCircle(
        c,
        r * 0.88,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.55
          ..blendMode = BlendMode.plus
          ..shader = SweepGradient(
            startAngle: phase * math.pi * 2,
            endAngle: phase * math.pi * 2 + math.pi * 2,
            colors: [
              for (final col in RarityHoloStyle.rainbow)
                col.withValues(alpha: rimA * 0.35),
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant RarityHoloSheenPainter old) =>
      old.t != t ||
      old.style.rarity != style.rarity ||
      old.intensityScale != intensityScale;
}

/// 可直接叠在圆形声片上的动画全息箔片层。
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

/// 静态圆形全息箔片叠层（揭晓／缩略等非动画场景）。
void paintRarityHoloOverlay({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required DiscRarity? rarity,
  required double elevatedBoost,
  double phase = 0.18,
}) {
  final style = RarityHoloStyle.of(rarity);
  canvas.save();
  canvas.translate(center.dx - radius, center.dy - radius);
  RarityHoloSheenPainter(
    t: phase.clamp(0.0, 1.0),
    style: style,
    intensityScale: 0.85 + 0.35 * elevatedBoost,
  ).paint(canvas, Size(radius * 2, radius * 2));
  canvas.restore();
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
