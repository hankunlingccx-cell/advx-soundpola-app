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

  static const _silver = Color(0xFFB8C4C0);
  static const _mint = Color(0xFF63E0CB);
  static const _blue = Color(0xFF56B8FF);
  static const _violet = Color(0xFF8A74FF);
  static const _pink = Color(0xFFF27BB5);
  static const _goldHint = Color(0xFFE8D5A3);

  static RarityHoloStyle of(DiscRarity? rarity) {
    final r = rarity ?? DiscRarity.n;
    return switch (r) {
      DiscRarity.n => const RarityHoloStyle(
          rarity: DiscRarity.n,
          spectrum: [_silver, _mint, _silver],
          accent: _silver,
          secondaryAccent: _mint,
          intensity: 0.28,
          bandStrength: 0.06,
          sweepSeconds: 5.2,
          bandCount: 1,
          rimWidth: 1.1,
          glowAlpha: 0.08,
          hasSecondaryRim: false,
          hasOuterPrism: false,
        ),
      DiscRarity.r => const RarityHoloStyle(
          rarity: DiscRarity.r,
          spectrum: [_mint, Color(0xFF7AEFDD), _blue, _mint],
          accent: _mint,
          secondaryAccent: _blue,
          intensity: 0.42,
          bandStrength: 0.10,
          sweepSeconds: 4.0,
          bandCount: 1,
          rimWidth: 1.3,
          glowAlpha: 0.14,
          hasSecondaryRim: false,
          hasOuterPrism: false,
        ),
      DiscRarity.sr => const RarityHoloStyle(
          rarity: DiscRarity.sr,
          spectrum: [_mint, _blue, _violet, _blue, _mint],
          accent: _blue,
          secondaryAccent: _violet,
          intensity: 0.55,
          bandStrength: 0.14,
          sweepSeconds: 3.2,
          bandCount: 2,
          rimWidth: 1.5,
          glowAlpha: 0.20,
          hasSecondaryRim: true,
          hasOuterPrism: true,
        ),
      DiscRarity.ssr => const RarityHoloStyle(
          rarity: DiscRarity.ssr,
          spectrum: [_mint, _blue, _violet, _pink, _goldHint, _mint],
          accent: _pink,
          secondaryAccent: _violet,
          intensity: 0.68,
          bandStrength: 0.18,
          sweepSeconds: 2.6,
          bandCount: 3,
          rimWidth: 1.7,
          glowAlpha: 0.28,
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

/// 卡面镭射扫光层：按 [RarityHoloStyle] 区分光谱与绚烂程度。
/// 旋转扫光与高光带均以角位移驱动，保证 0→1 循环无接缝突变。
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
    final strength = (style.intensity * intensityScale).clamp(0.0, 1.0);
    // 连续角位移；AnimationController.repeat 在 0/1 等价，无跳变。
    final angle = t * math.pi * 2;

    // 主棱镜：首尾同色，SweepGradient 旋转无接缝。
    final spectrum = _loopedSpectrum(style.spectrum, strength);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.softLight
        ..shader = SweepGradient(
          startAngle: angle,
          endAngle: angle + math.pi * 2,
          colors: spectrum,
          stops: _stopsFor(spectrum.length),
        ).createShader(rect),
    );

    // 高光带：整层旋转，而非平移 begin/end（平移会在 cycle 端点突变）。
    for (var i = 0; i < style.bandCount; i++) {
      final hue = style.spectrum[i % style.spectrum.length];
      final bandAngle = angle * (1.0 + i * 0.17) + i * (math.pi * 2 / style.bandCount);
      final bandAlpha = (style.bandStrength * strength * 0.55).clamp(0.0, 0.22);
      final whiteAlpha = (0.04 * strength).clamp(0.0, 0.06);

      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(bandAngle);
      canvas.translate(-c.dx, -c.dy);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.softLight
          ..shader = LinearGradient(
            begin: const Alignment(-0.35, -1.0),
            end: const Alignment(0.35, 1.0),
            colors: [
              Colors.transparent,
              hue.withValues(alpha: bandAlpha * 0.35),
              Colors.white.withValues(alpha: whiteAlpha),
              hue.withValues(alpha: bandAlpha),
              Colors.transparent,
            ],
            stops: const [0.30, 0.44, 0.50, 0.56, 0.70],
          ).createShader(rect),
      );
      canvas.restore();
    }

    // SR+：外缘棱镜环，同样首尾闭合 + 角旋转。
    if (style.hasOuterPrism) {
      final rimColors = _loopedSpectrum(
        style.spectrum,
        strength * 0.55,
      );
      canvas.drawCircle(
        c,
        r * 0.92,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * (style.rarity == DiscRarity.ssr ? 0.07 : 0.05)
          ..blendMode = BlendMode.softLight
          ..shader = SweepGradient(
            startAngle: -angle * 0.85,
            endAngle: -angle * 0.85 + math.pi * 2,
            colors: rimColors,
            stops: _stopsFor(rimColors.length),
          ).createShader(rect)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            style.rarity == DiscRarity.ssr ? 2.0 : 1.2,
          ),
      );
    }
  }

  /// 环形光谱：首尾颜色一致，旋转时无色差接缝。
  List<Color> _loopedSpectrum(List<Color> src, double strength) {
    if (src.isEmpty) return [Colors.transparent, Colors.transparent];
    final peak = (0.22 + 0.28 * strength).clamp(0.12, 0.48);
    final mids = <Color>[];
    for (var i = 0; i < src.length; i++) {
      final wave = 0.55 + 0.45 * math.sin(i / src.length * math.pi);
      mids.add(src[i].withValues(alpha: (peak * wave).clamp(0.0, 0.5)));
    }
    // Close the loop with the same color as the first stop.
    return [...mids, mids.first];
  }

  List<double> _stopsFor(int n) {
    if (n <= 1) return const [0.0];
    return List.generate(n, (i) => i / (n - 1));
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

/// 静态圆形镭射叠层（无动画时钟时用于 CustomPainter 内嵌，如 DiscFacePainter）。
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
      (style.intensity * (0.55 + 0.25 * elevatedBoost)).clamp(0.0, 0.75);
  final rect = Rect.fromCircle(center: center, radius: radius);
  final angle = phase * math.pi * 2;

  final colors = <Color>[
    for (var i = 0; i < style.spectrum.length; i++)
      style.spectrum[i].withValues(
        alpha: strength * (0.18 + 0.08 * (i / style.spectrum.length)),
      ),
  ];
  // Close loop for seamless static sheen.
  colors.add(colors.first);

  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..blendMode = BlendMode.softLight
      ..shader = SweepGradient(
        startAngle: angle,
        colors: colors,
      ).createShader(rect),
  );

  if (style.bandCount >= 2) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle * 0.7);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..blendMode = BlendMode.softLight
        ..shader = LinearGradient(
          begin: const Alignment(-0.4, -1),
          end: const Alignment(0.4, 1),
          colors: [
            Colors.transparent,
            style.accent.withValues(alpha: style.bandStrength * 0.45 * strength),
            style.secondaryAccent
                .withValues(alpha: style.bandStrength * 0.3 * strength),
            Colors.transparent,
          ],
          stops: const [0.32, 0.48, 0.56, 0.72],
        ).createShader(rect),
    );
    canvas.restore();
  }
}

/// 等级描边色：主 rim + 可选次 rim。
(Color, Color?) rarityRimColors(DiscRarity? rarity, {required bool elevated}) {
  final s = RarityHoloStyle.of(rarity);
  final main = s.accent.withValues(alpha: elevated ? 0.9 : 0.55);
  final second = s.hasSecondaryRim
      ? s.secondaryAccent.withValues(alpha: elevated ? 0.45 : 0.28)
      : null;
  return (main, second);
}
