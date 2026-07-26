import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/disc_rarity.dart';
import '../data/sound_repository.dart';
import '../services/audio_playback_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'baked_sound_visual.dart';
import 'design_components.dart';
import 'disc_texture.dart';
import 'rarity_holo.dart';
import 'ssr_aura_layer.dart';

/// 卡面元信息侧重点：链上资产字段 or 分享场景（地点／日期＋水印）。
enum SoundNftCardVariant { chain, share }

/// 声片 NFT 稀有度卡：Press 完成翻面揭晓 与 分类播放页分享卡共用。
/// 分享变体对齐 Figma 四档收藏卡（外壳／稀有度描边／白底信息板／环绕印章）。
class SoundNftCard extends StatelessWidget {
  const SoundNftCard({
    super.key,
    required this.item,
    this.animateVisual = true,
    this.compact = false,
    this.variant = SoundNftCardVariant.chain,
    this.useDiscTexture = false,
  });

  final SoundMemory item;
  final bool animateVisual;
  final bool compact;
  final SoundNftCardVariant variant;

  /// 分享场景优先使用稳定贴图，而非重新渲染声音可视化。
  final bool useDiscTexture;

  @override
  Widget build(BuildContext context) {
    if (variant == SoundNftCardVariant.share) {
      return _ShareCollectibleCard(
        item: item,
        compact: compact,
        animateVisual: animateVisual,
        useDiscTexture: useDiscTexture,
      );
    }
    return _ChainAssetCard(
      item: item,
      compact: compact,
      animateVisual: animateVisual,
      useDiscTexture: useDiscTexture,
    );
  }
}

/// Press 完成页：链上凭证信息卡（克制仪器感）。
class _ChainAssetCard extends StatelessWidget {
  const _ChainAssetCard({
    required this.item,
    required this.compact,
    required this.animateVisual,
    required this.useDiscTexture,
  });

  final SoundMemory item;
  final bool compact;
  final bool animateVisual;
  final bool useDiscTexture;

  RarityHoloStyle get _holo => RarityHoloStyle.of(item.discRarity);
  bool get _isSsr => item.discRarity == DiscRarity.ssr;
  Color get _accent => _holo.accent;

  @override
  Widget build(BuildContext context) {
    final visualSize = compact ? 118.0 : 150.0;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? AppSpacing.item : AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: _accent.withValues(alpha: _isSsr ? 0.5 : 0.24),
          width: _isSsr ? 1.3 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: _isSsr ? 0.32 : 0.16),
            blurRadius: _isSsr ? 48 : 26,
            spreadRadius: _isSsr ? 2 : 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              RarityChip(rarity: item.discRarity, compact: compact),
              const SizedBox(width: 8),
              const Text(
                'NFT',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
            ],
          ),
          SizedBox(height: compact ? AppSpacing.tight : AppSpacing.item),
          _DiscHero(
            item: item,
            size: visualSize,
            animateVisual: animateVisual,
            useDiscTexture: useDiscTexture,
          ),
          SizedBox(height: compact ? AppSpacing.item : AppSpacing.section),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: compact ? 16 : 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.category,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: compact ? AppSpacing.tight : AppSpacing.item),
          const Divider(height: 1, color: AppColors.borderSubtle),
          SizedBox(height: compact ? 4 : 8),
          _metaRow('声片编号', item.discId ?? '—'),
          _metaRow('数字资产编号', _abbreviate(item.assetId)),
          _metaRow(
            '上链时间',
            item.chainedAt != null ? formatRecordedAt(item.chainedAt!) : '—',
          ),
        ],
      ),
    );
  }

  String _abbreviate(String? id) {
    if (id == null || id.isEmpty) return '—';
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}…${id.substring(id.length - 4)}';
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分享用收藏卡：对齐 Figma 声卡分享视觉（N/R/SR/SSR 四档描边与顶栏）。
/// 结构：灰边外壳 → 黑底稀有度描边 → 顶部等级 → 中间声卡视觉 → 白底信息板＋环绕印章 → 品牌脚注。
class _ShareCollectibleCard extends StatelessWidget {
  const _ShareCollectibleCard({
    required this.item,
    required this.compact,
    required this.animateVisual,
    required this.useDiscTexture,
  });

  final SoundMemory item;
  final bool compact;
  final bool animateVisual;
  final bool useDiscTexture;

  DiscRarity get _rarity => item.discRarity ?? DiscRarity.n;

  /// Figma 分享卡专属描边／印章色（与稿面一致，不完全复用全息 accent）。
  Color get _frameAccent => switch (_rarity) {
        DiscRarity.n => Colors.white,
        DiscRarity.r => const Color(0xFF38D7D0),
        DiscRarity.sr => const Color(0xFF7454EB),
        DiscRarity.ssr => const Color(0xFFED4F8F),
      };

  Color get _sealFill => switch (_rarity) {
        DiscRarity.n => const Color(0xFF212121),
        DiscRarity.r => const Color(0xFF63E0CB),
        DiscRarity.sr => const Color(0xFF7454EB),
        DiscRarity.ssr => const Color(0xFFED4F8F),
      };

  bool get _hasColorBanner => _rarity != DiscRarity.n;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        // Figma 设计宽 840；手机分享预览约 300–340。
        final w = (compact ? maxW * 0.92 : maxW).clamp(260.0, 420.0);
        final s = w / 840.0;
        final h = w * (1240 / 840);

        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF272728),
                borderRadius: BorderRadius.circular(60 * s),
                border: Border.all(
                  color: const Color(0xFF505050),
                  width: (2 * s).clamp(1.0, 2.0),
                ),
              ),
              padding: EdgeInsets.all(20 * s),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(44 * s),
                  border: Border.all(
                    color: _frameAccent,
                    width: (4 * s).clamp(1.5, 3.5),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _ShareRarityHeader(
                      code: _rarity.code,
                      accent: _frameAccent,
                      scale: s,
                      coloredBanner: _hasColorBanner,
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12 * s),
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: LayoutBuilder(
                              builder: (context, c) {
                                final side = c.maxWidth;
                                // 收藏／分享卡中部固定为声音可视化，不用稀有度声片贴图。
                                return _DiscHero(
                                  item: item,
                                  size: side,
                                  animateVisual: animateVisual,
                                  useDiscTexture: false,
                                  showHolo: false,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(10 * s, 0, 10 * s, 8 * s),
                      child: _ShareInfoPanel(
                        item: item,
                        scale: s,
                        sealFill: _sealFill,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(36 * s, 0, 36 * s, 18 * s),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'SoundPola',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: (36 * s).clamp(12.0, 18.0),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          Text(
                            '已写入声片',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: (28 * s).clamp(10.0, 14.0),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ShareRarityHeader extends StatelessWidget {
  const _ShareRarityHeader({
    required this.code,
    required this.accent,
    required this.scale,
    required this.coloredBanner,
  });

  final String code;
  final Color accent;
  final double scale;
  final bool coloredBanner;

  @override
  Widget build(BuildContext context) {
    final fontSize = (88 * scale).clamp(28.0, 46.0);
    final bannerH = (124 * scale).clamp(44.0, 64.0);

    if (!coloredBanner) {
      return Padding(
        padding: EdgeInsets.only(top: 18 * scale, bottom: 4 * scale),
        child: Column(
          children: [
            Text(
              code,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w400,
                height: 0.85,
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 6 * scale),
            SizedBox(
              height: 18 * scale,
              width: double.infinity,
              child: CustomPaint(
                painter: _NNotchLinePainter(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: bannerH,
      width: double.infinity,
      child: CustomPaint(
        painter: _RarityBannerPainter(color: accent),
        child: Center(
          child: Text(
            code,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize * 0.85,
              fontWeight: FontWeight.w400,
              height: 1,
              letterSpacing: code.length > 1 ? 1.5 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _NNotchLinePainter extends CustomPainter {
  _NNotchLinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.08, h * 0.25)
      ..lineTo(w * 0.38, h * 0.25)
      ..lineTo(w * 0.45, h * 0.85)
      ..lineTo(w * 0.55, h * 0.85)
      ..lineTo(w * 0.62, h * 0.25)
      ..lineTo(w * 0.92, h * 0.25);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _NNotchLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _RarityBannerPainter extends CustomPainter {
  _RarityBannerPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final w = size.width;
    final h = size.height;
    final notchW = w * 0.22;
    final notchD = h * 0.28;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h - notchD)
      ..lineTo(w * 0.5 + notchW / 2, h - notchD)
      ..lineTo(w * 0.5, h)
      ..lineTo(w * 0.5 - notchW / 2, h - notchD)
      ..lineTo(0, h - notchD)
      ..close();
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(covariant _RarityBannerPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ShareInfoPanel extends StatelessWidget {
  const _ShareInfoPanel({
    required this.item,
    required this.scale,
    required this.sealFill,
  });

  final SoundMemory item;
  final double scale;
  final Color sealFill;

  String get _discLabel {
    final id = item.discId;
    if (id == null || id.isEmpty) return '#SP-————';
    return id.startsWith('#') ? id : '#$id';
  }

  String get _assetLabel {
    final id = item.assetId ?? item.contentId ?? item.id;
    return id.toLowerCase();
  }

  String get _dateLabel {
    final dt = item.recordedAt.toLocal();
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$y.$mo.$d $h:$mi';
  }

  @override
  Widget build(BuildContext context) {
    final seal = (190 * scale).clamp(56.0, 88.0);
    final titleSize = (46 * scale).clamp(15.0, 22.0);
    final idSize = (36 * scale).clamp(13.0, 17.0);
    final metaSize = (30 * scale).clamp(11.0, 14.0);
    final assetLabelSize = (28 * scale).clamp(10.0, 13.0);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(18 * scale, 16 * scale, 14 * scale, 14 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(42 * scale),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                    Text(
                      _discLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: idSize,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: 8 * scale),
                    Text(
                      item.locationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: metaSize,
                        fontWeight: FontWeight.w400,
                        height: 1.15,
                      ),
                    ),
                    Text(
                      _dateLabel,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: metaSize,
                        fontWeight: FontWeight.w400,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8 * scale),
              _CyberSeal(size: seal, fill: sealFill),
            ],
          ),
          SizedBox(height: 12 * scale),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 16 * scale,
              vertical: 8 * scale,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFD0D0D0),
              borderRadius: BorderRadius.circular(24 * scale),
            ),
            child: Row(
              children: [
                Text(
                  '资产编号',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: assetLabelSize,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                SizedBox(width: 10 * scale),
                Expanded(
                  child: Text(
                    _assetLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: assetLabelSize,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CyberSeal extends StatelessWidget {
  const _CyberSeal({required this.size, required this.fill});

  final double size;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: size * 0.12,
            offset: Offset(size * 0.06, size * 0.05),
          ),
        ],
      ),
      child: CustomPaint(
        size: Size(size, size),
        painter: _CyberSealPainter(fill: fill),
      ),
    );
  }
}

class _CyberSealPainter extends CustomPainter {
  _CyberSealPainter({required this.fill});
  final Color fill;

  static const _ringText = 'CYBERPUNKVIBES.';

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    canvas.drawCircle(c, r, Paint()..color = fill);

    // Center star / asterisk glyph.
    final starR = r * 0.28;
    final star = Path();
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final outer = Offset(c.dx + math.cos(a) * starR, c.dy + math.sin(a) * starR);
      final a2 = a + math.pi / 8;
      final inner = Offset(
        c.dx + math.cos(a2) * starR * 0.38,
        c.dy + math.sin(a2) * starR * 0.38,
      );
      if (i == 0) {
        star.moveTo(outer.dx, outer.dy);
      } else {
        star.lineTo(outer.dx, outer.dy);
      }
      star.lineTo(inner.dx, inner.dy);
    }
    star.close();
    canvas.drawPath(star, Paint()..color = Colors.white);

    // Circular caption — two revolutions of CYBERPUNKVIBES.
    final text = '$_ringText$_ringText';
    final fontSize = (size.width * 0.088).clamp(6.0, 11.0);
    final radius = r * 0.78;
    final total = text.length;
    for (var i = 0; i < total; i++) {
      final angle = -math.pi / 2 + (i / total) * math.pi * 2;
      canvas.save();
      canvas.translate(
        c.dx + math.cos(angle) * radius,
        c.dy + math.sin(angle) * radius,
      );
      canvas.rotate(angle + math.pi / 2);
      final tp = TextPainter(
        text: TextSpan(
          text: text[i],
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CyberSealPainter oldDelegate) =>
      oldDelegate.fill != fill;
}

class _DiscHero extends StatelessWidget {
  const _DiscHero({
    required this.item,
    required this.size,
    required this.animateVisual,
    required this.useDiscTexture,
    this.showHolo = true,
  });

  final SoundMemory item;
  final double size;
  final bool animateVisual;
  final bool useDiscTexture;

  /// 分享卡中部：纯声音可视化（无镭射、无描边、无光晕叠色）。
  final bool showHolo;

  RarityHoloStyle get _holo => RarityHoloStyle.of(item.discRarity);
  bool get _isSsr => item.discRarity == DiscRarity.ssr;
  Color get _accent => _holo.accent;

  @override
  Widget build(BuildContext context) {
    final holo = _holo;
    final (rimMain, rimSecond) = rarityRimColors(
      item.discRarity,
      elevated: true,
    );
    final core = ClipOval(
      child: useDiscTexture
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  discTextureFor(item.discRarity),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
                if (showHolo)
                  RarityHoloOverlay(
                    rarity: item.discRarity,
                    intensityScale: 1.0,
                    enabled: animateVisual,
                  ),
              ],
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                BakedSoundVisual(
                  item: item,
                  playing: animateVisual,
                  positionMsListenable: AudioPlaybackService.instance.positionMs,
                  fit: BoxFit.cover,
                ),
                if (showHolo)
                  RarityHoloOverlay(
                    rarity: item.discRarity,
                    intensityScale: 1.0,
                    enabled: animateVisual,
                  ),
              ],
            ),
    );

    // 分享卡：纯圆形可视化，无描边、无光晕、无叠色。
    if (!showHolo && !useDiscTexture) {
      return SizedBox(width: size, height: size, child: core);
    }

    return SizedBox(
      width: size,
      height: size,
      child: SsrAuraLayer(
        size: size,
        enabled: _isSsr && animateVisual,
        playing: animateVisual,
        energy: 0.45,
        intensity: 1,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              bottom: 2,
              child: IgnorePointer(
                child: Container(
                  width: size * 0.72,
                  height: size * 0.18,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.35),
                        blurRadius: 22,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            core,
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: rimMain,
                    width: holo.rimWidth,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withValues(alpha: holo.glowAlpha),
                      blurRadius: 18 + holo.glowAlpha * 40,
                      spreadRadius: _isSsr ? 1.5 : 0.4,
                    ),
                    if (holo.rarity.index >= DiscRarity.sr.index)
                      BoxShadow(
                        color: holo.secondaryAccent.withValues(alpha: 0.18),
                        blurRadius: 28,
                      ),
                  ],
                ),
              ),
            ),
            if (rimSecond != null)
              IgnorePointer(
                child: Container(
                  width: size - 4,
                  height: size - 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: rimSecond, width: 0.85),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
