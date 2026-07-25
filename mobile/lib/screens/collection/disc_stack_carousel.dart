import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/disc_rarity.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/disc_texture.dart';
import '../../widgets/ssr_aura_layer.dart';

/// 横向三维声片堆栈：PageController 驱动物理滑动，Stack 控制遮挡层级。
class DiscStackCarousel extends StatefulWidget {
  const DiscStackCarousel({
    super.key,
    required this.itemCount,
    required this.seedAt,
    required this.titleAt,
    required this.initialIndex,
    required this.onIndexChanged,
    required this.onCenterTap,
    this.rarityAt,
  });

  final int itemCount;
  final int Function(int index) seedAt;
  final String Function(int index) titleAt;
  final DiscRarity? Function(int index)? rarityAt;
  final int initialIndex;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onCenterTap;

  @override
  State<DiscStackCarousel> createState() => _DiscStackCarouselState();
}

class _DiscStackCarouselState extends State<DiscStackCarousel> {
  static const _viewportFraction = 0.42;
  late final PageController _controller;
  int _index = 0;
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, math.max(0, widget.itemCount - 1));
    _page = _index.toDouble();
    _controller = PageController(
      initialPage: _index,
      viewportFraction: _viewportFraction,
    );
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant DiscStackCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount && widget.itemCount > 0) {
      final next = _index.clamp(0, widget.itemCount - 1);
      if (next != _index) {
        _index = next;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_controller.hasClients) return;
          _controller.jumpToPage(_index);
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients || !_controller.position.haveDimensions) return;
    final page = _controller.page ?? _index.toDouble();
    if ((page - _page).abs() < 0.001) return;
    setState(() => _page = page);
  }

  Future<void> _goTo(int index) async {
    if (index < 0 || index >= widget.itemCount) return;
    HapticFeedback.selectionClick();
    await _controller.animateToPage(
      index,
      duration: AppMotion.slow,
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageSettled(int index) {
    if (_index == index) return;
    _index = index;
    final rarity = widget.rarityAt?.call(index);
    if (rarity == DiscRarity.ssr) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    widget.onIndexChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();

    return SizedBox(
      height: 220,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final centerSize = math.min(168.0, width * 0.46);

          return Stack(
            alignment: Alignment.center,
            children: [
              // 视觉层：按距离排序，远处先画、中心最后（最高层级）
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final page = _controller.hasClients &&
                          _controller.position.haveDimensions
                      ? (_controller.page ?? _page)
                      : _page;

                  final order = List<int>.generate(widget.itemCount, (i) => i);
                  order.sort((a, b) {
                    final da = (a - page).abs();
                    final db = (b - page).abs();
                    return db.compareTo(da);
                  });

                  return Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      for (final i in order)
                        _buildDisc(
                          index: i,
                          page: page,
                          centerSize: centerSize,
                          trackWidth: width,
                        ),
                    ],
                  );
                },
              ),
              // 手势层：透明 PageView 提供惯性与吸附
              PageView.builder(
                controller: _controller,
                itemCount: widget.itemCount,
                onPageChanged: _onPageSettled,
                physics: const BouncingScrollPhysics(
                  parent: PageScrollPhysics(),
                ),
                itemBuilder: (context, index) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final current = _controller.page?.round() ?? _index;
                      if (index == current) {
                        widget.onCenterTap();
                      } else {
                        _goTo(index);
                      }
                    },
                    child: const ColoredBox(color: Colors.transparent),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDisc({
    required int index,
    required double page,
    required double centerSize,
    required double trackWidth,
  }) {
    final delta = index - page;
    final absDelta = delta.abs();
    final t = absDelta.clamp(0.0, 2.5);

    // 透视：越远越小、越暗、越透明，并横向收拢形成重叠堆栈
    final scale = ui.lerpDouble(1.0, 0.58, (t / 2.2).clamp(0.0, 1.0))!;
    final opacity = ui.lerpDouble(1.0, 0.38, (t / 2.4).clamp(0.0, 1.0))!;
    final brightness = ui.lerpDouble(1.0, 0.55, (t / 2.0).clamp(0.0, 1.0))!;
    final overlapPull = delta * centerSize * 0.38;
    final baseSlot = delta * trackWidth * _viewportFraction;
    final dx = baseSlot - overlapPull;
    final dy = absDelta * 4.0;
    final shadowBlur = ui.lerpDouble(22, 8, (t / 2).clamp(0.0, 1.0))!;
    final shadowAlpha = ui.lerpDouble(0.55, 0.18, (t / 2).clamp(0.0, 1.0))!;
    final depth = (1.0 - (t / 2.5).clamp(0.0, 1.0));

    final size = centerSize * scale;
    final isCenter = absDelta < 0.08;

    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.scale(
        scale: 1.0,
        child: Opacity(
          opacity: opacity,
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(_brightnessMatrix(brightness)),
            child: Semantics(
              label: widget.titleAt(index),
              selected: isCenter,
              child: _PlayDisc(
                size: size,
                seed: widget.seedAt(index),
                rarity: widget.rarityAt?.call(index),
                elevated: isCenter,
                shadowBlur: shadowBlur,
                shadowAlpha: shadowAlpha,
                thickness: 2.0 + depth * 3.5,
                animateEdge: isCenter,
                pageDelta: delta,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<double> _brightnessMatrix(double b) {
    // 简单亮度矩阵，远处声片略暗
    return <double>[
      b, 0, 0, 0, 0,
      0, b, 0, 0, 0,
      0, 0, b, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }
}

class _PlayDisc extends StatelessWidget {
  const _PlayDisc({
    required this.size,
    required this.seed,
    required this.elevated,
    required this.shadowBlur,
    required this.shadowAlpha,
    required this.thickness,
    this.rarity,
    this.animateEdge = false,
    this.pageDelta = 0,
  });

  final double size;
  final int seed;
  final DiscRarity? rarity;
  final bool elevated;
  final double shadowBlur;
  final double shadowAlpha;
  final double thickness;
  final bool animateEdge;
  final double pageDelta;

  Color get _glow {
    return AppColors.accent.withValues(alpha: elevated ? 0.32 : 0.12);
  }

  @override
  Widget build(BuildContext context) {
    final isSsr = SsrAuraLayer.isSsr(rarity);
    final texture = discTextureFor(seed);
    final face = ClipOval(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.white),
          Opacity(
            opacity: elevated ? 0.52 : 0.42,
            child: Image.asset(
              texture,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          ColoredBox(
            color: Colors.white.withValues(alpha: elevated ? 0.06 : 0.12),
          ),
          // 玻璃高光
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(-0.8, -1),
                end: const Alignment(0.4, 0.35),
                colors: [
                  Colors.white.withValues(alpha: elevated ? 0.32 : 0.2),
                  Colors.white.withValues(alpha: 0.06),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.08),
                ],
                stops: const [0.0, 0.28, 0.55, 1.0],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: elevated
                    ? AppColors.accent.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.28),
                width: elevated ? 1.4 : 1,
              ),
            ),
          ),
        ],
      ),
    );

    return SizedBox(
      width: size,
      height: size + thickness,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: thickness,
            child: Container(
              width: size * 0.96,
              height: size * 0.96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A1A1A),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: shadowAlpha),
                    blurRadius: shadowBlur,
                    offset: Offset(0, elevated ? 14 : 8),
                  ),
                  if (elevated || rarity != null)
                    BoxShadow(
                      color: _glow,
                      blurRadius: 30,
                      spreadRadius: 1,
                    ),
                ],
              ),
            ),
          ),
          SsrAuraLayer(
            size: size,
            enabled: isSsr,
            intensity: elevated ? 1.0 : 0.2,
            parallax: isSsr
                ? ssrParallaxFromDelta(
                    pageDelta,
                    maxPx: elevated ? 3.5 : 1.5,
                  )
                : Offset.zero,
            child: face,
          ),
        ],
      ),
    );
  }
}

/// 抽象几何声片面：黑 / 白 / 薄荷青为主，少量蓝紫粉；无描边、无中心孔。
class DiscFacePainter extends CustomPainter {
  DiscFacePainter({
    required this.seed,
    required this.elevated,
    this.rarity,
    this.edgePulse = false,
  });

  final int seed;
  final bool elevated;
  final DiscRarity? rarity;
  final bool edgePulse;

  static const _mint = Color(0xFF63E0CB);
  static const _blue = Color(0xFF4FA9E8);
  static const _purple = Color(0xFF7667E8);
  static const _pink = Color(0xFFD879C8);

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final r = size.width / 2;
    final c = Offset(r, r);
    final rect = Rect.fromCircle(center: c, radius: r);

    canvas.save();
    canvas.clipPath(Path()..addOval(rect));

    // 底色：深黑或近白，按种子二分
    final lightBase = rnd.nextBool();
    final base = lightBase ? const Color(0xFFF2F5F4) : const Color(0xFF0A0C0B);
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    final accents = <Color>[_mint, _blue, _purple, _pink];
    final accent = accents[rnd.nextInt(accents.length)];
    final secondary = accents[(rnd.nextInt(accents.length) + 1) % accents.length];

    final style = seed.abs() % 4;
    switch (style) {
      case 0:
        _paintRibbons(canvas, c, r, rnd, accent, secondary, lightBase);
      case 1:
        _paintPetals(canvas, c, r, rnd, accent, lightBase);
      case 2:
        _paintBlocks(canvas, c, r, rnd, accent, secondary, lightBase);
      default:
        _paintOrbit(canvas, c, r, rnd, accent, secondary, lightBase);
    }

    // 边缘高光（实体薄片感，非光盘刻痕）
    final rim = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          (lightBase ? Colors.black : Colors.white)
              .withValues(alpha: lightBase ? 0.06 : 0.10),
        ],
        stops: const [0.78, 1.0],
      ).createShader(rect);
    canvas.drawCircle(c, r, rim);

    final topSheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.center,
        colors: [
          Colors.white.withValues(alpha: elevated ? 0.28 : 0.16),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawCircle(c, r, topSheen);

    // 全等级镭射折射叠层（稀有度差异后续由贴图区分）
    final holoStrength = elevated ? 0.55 : 0.38;
    final holo = Paint()
      ..blendMode = BlendMode.softLight
      ..shader = SweepGradient(
        colors: [
          _mint.withValues(alpha: 0),
          _mint.withValues(alpha: holoStrength),
          _blue.withValues(alpha: holoStrength * 0.85),
          _purple.withValues(alpha: holoStrength * 0.75),
          _pink.withValues(alpha: holoStrength * 0.75),
          _mint.withValues(alpha: holoStrength * 0.9),
          _mint.withValues(alpha: 0),
        ],
      ).createShader(rect);
    canvas.drawCircle(c, r, holo);

    canvas.restore();

    // 统一镭射边缘高光
    final edgeColor = _mint.withValues(alpha: elevated ? 0.9 : 0.45);
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = elevated ? 1.6 : 1.1
        ..color = edgeColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, edgePulse ? 3.2 : 1.6),
    );
    if (elevated) {
      canvas.drawCircle(
        c,
        r - 4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = _pink.withValues(alpha: 0.3),
      );
    }
  }

  void _paintRibbons(
    Canvas canvas,
    Offset c,
    double r,
    math.Random rnd,
    Color a,
    Color b,
    bool light,
  ) {
    for (var i = 0; i < 5; i++) {
      final path = Path();
      final start = -r + rnd.nextDouble() * r * 0.4;
      path.moveTo(c.dx - r, c.dy + start);
      path.cubicTo(
        c.dx - r * 0.3,
        c.dy + start + rnd.nextDouble() * r * 0.8 - r * 0.2,
        c.dx + r * 0.3,
        c.dy + start + rnd.nextDouble() * r * 0.6 - r * 0.1,
        c.dx + r,
        c.dy + start + rnd.nextDouble() * r * 0.5,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * (0.08 + rnd.nextDouble() * 0.12)
          ..strokeCap = StrokeCap.round
          ..color = (i.isEven ? a : b).withValues(
            alpha: light ? 0.55 : 0.7,
          ),
      );
    }
  }

  void _paintPetals(
    Canvas canvas,
    Offset c,
    double r,
    math.Random rnd,
    Color a,
    bool light,
  ) {
    final petals = 5 + rnd.nextInt(3);
    for (var i = 0; i < petals; i++) {
      final ang = (i / petals) * math.pi * 2 + rnd.nextDouble() * 0.2;
      final pr = r * (0.35 + rnd.nextDouble() * 0.35);
      final pc = Offset(c.dx + math.cos(ang) * pr * 0.45,
          c.dy + math.sin(ang) * pr * 0.45);
      canvas.drawCircle(
        pc,
        pr * 0.55,
        Paint()..color = a.withValues(alpha: light ? 0.35 : 0.5),
      );
    }
    canvas.drawCircle(
      c,
      r * 0.18,
      Paint()
        ..color = (light ? const Color(0xFF0A0C0B) : Colors.white)
            .withValues(alpha: 0.85),
    );
  }

  void _paintBlocks(
    Canvas canvas,
    Offset c,
    double r,
    math.Random rnd,
    Color a,
    Color b,
    bool light,
  ) {
    final n = 4 + rnd.nextInt(3);
    for (var i = 0; i < n; i++) {
      final w = r * (0.35 + rnd.nextDouble() * 0.7);
      final h = r * (0.12 + rnd.nextDouble() * 0.25);
      final ox = (rnd.nextDouble() - 0.5) * r * 1.1;
      final oy = (rnd.nextDouble() - 0.5) * r * 1.1;
      final rot = rnd.nextDouble() * math.pi;
      canvas.save();
      canvas.translate(c.dx + ox, c.dy + oy);
      canvas.rotate(rot);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          Radius.circular(h * 0.35),
        ),
        Paint()
          ..color = (i.isEven ? a : b).withValues(alpha: light ? 0.45 : 0.65),
      );
      canvas.restore();
    }
  }

  void _paintOrbit(
    Canvas canvas,
    Offset c,
    double r,
    math.Random rnd,
    Color a,
    Color b,
    bool light,
  ) {
    for (var i = 0; i < 4; i++) {
      final rr = r * (0.25 + i * 0.18 + rnd.nextDouble() * 0.05);
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * (0.04 + rnd.nextDouble() * 0.05)
          ..color = (i.isEven ? a : b).withValues(alpha: light ? 0.4 : 0.6),
      );
    }
    final dots = 6 + rnd.nextInt(5);
    for (var i = 0; i < dots; i++) {
      final ang = rnd.nextDouble() * math.pi * 2;
      final rad = r * (0.2 + rnd.nextDouble() * 0.65);
      canvas.drawCircle(
        Offset(c.dx + math.cos(ang) * rad, c.dy + math.sin(ang) * rad),
        r * (0.03 + rnd.nextDouble() * 0.05),
        Paint()..color = a.withValues(alpha: 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant DiscFacePainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.elevated != elevated ||
      oldDelegate.rarity != rarity ||
      oldDelegate.edgePulse != edgePulse;
}
