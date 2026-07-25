import 'package:flutter/material.dart';

import '../data/disc_rarity.dart';
import '../data/sound_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'design_components.dart';
import 'disc_texture.dart';
import 'rarity_holo.dart';
import 'sound_visual.dart';
import 'ssr_aura_layer.dart';

/// 卡面元信息侧重点：链上资产字段 or 分享场景（地点／日期＋水印）。
enum SoundNftCardVariant { chain, share }

/// 声片 NFT 稀有度卡：Press 完成翻面揭晓 与 分类播放页分享卡共用。
/// 分享变体为游戏化收藏卡＋高级 iOS 玻璃质感。
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

/// 分享用收藏卡：游戏化稀有度徽章 + iOS 玻璃／镜面层次。
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

  RarityHoloStyle get _holo => RarityHoloStyle.of(item.discRarity);
  bool get _isSsr => item.discRarity == DiscRarity.ssr;
  Color get _accent => _holo.accent;
  String get _rankCode => item.discRarity?.code ?? 'N';
  String get _rankLabel => item.discRarity?.label ?? '普通';

  @override
  Widget build(BuildContext context) {
    final discSize = compact ? 132.0 : 168.0;
    final radius = compact ? 26.0 : 30.0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 28,
            offset: const Offset(0, 16),
            spreadRadius: -6,
          ),
          BoxShadow(
            color: _accent.withValues(alpha: _isSsr ? 0.38 : 0.22),
            blurRadius: _isSsr ? 42 : 28,
            offset: const Offset(0, 8),
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            // Base glass plate
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(AppColors.surface2, _accent, 0.08)!,
                      AppColors.surface1,
                      Color.lerp(const Color(0xFF070A09), _accent, 0.06)!,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            // Soft rarity wash
            Positioned(
              top: -40,
              right: -30,
              child: IgnorePointer(
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _accent.withValues(alpha: _isSsr ? 0.28 : 0.16),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Specular top edge (iOS material highlight)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 1.2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: 0.42),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Hairline frame
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                      width: 0.7,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: _accent.withValues(alpha: _isSsr ? 0.45 : 0.22),
                      width: _isSsr ? 1.35 : 1.0,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 20,
                compact ? 14 : 18,
                compact ? 16 : 20,
                compact ? 16 : 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MEMORY SEALED',
                              style: TextStyle(
                                color: _accent.withValues(alpha: 0.85),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'COLLECTIBLE · $_rankCode',
                              style: TextStyle(
                                color: AppColors.textTertiary.withValues(
                                  alpha: 0.9,
                                ),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _RaritySeal(
                        rarity: item.discRarity,
                        code: _rankCode,
                        label: _rankLabel,
                        accent: _accent,
                        compact: compact,
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 14 : 18),
                  _DiscHero(
                    item: item,
                    size: discSize,
                    animateVisual: animateVisual,
                    useDiscTexture: useDiscTexture,
                  ),
                  SizedBox(height: compact ? 14 : 18),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: compact ? 18 : 22,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.category.toUpperCase(),
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.6,
                    ),
                  ),
                  SizedBox(height: compact ? 14 : 18),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCapsule(
                          label: '地点',
                          value: item.locationLabel,
                          accent: _accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCapsule(
                          label: '日期',
                          value: formatRecordedAt(item.recordedAt),
                          accent: _accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCapsule(
                          label: '声片',
                          value: _shortId(item.discId),
                          accent: _accent,
                          mono: true,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 14 : 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 18,
                        height: 1,
                        color: _accent.withValues(alpha: 0.35),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'SoundPola',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3.2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 18,
                        height: 1,
                        color: _accent.withValues(alpha: 0.35),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortId(String? id) {
    if (id == null || id.isEmpty) return '—';
    if (id.length <= 8) return id;
    return '${id.substring(0, 4)}…${id.substring(id.length - 2)}';
  }
}

class _RaritySeal extends StatelessWidget {
  const _RaritySeal({
    required this.rarity,
    required this.code,
    required this.label,
    required this.accent,
    required this.compact,
  });

  final DiscRarity? rarity;
  final String code;
  final String label;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 48.0 : 56.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.35),
                  accent.withValues(alpha: 0.08),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.4),
                  blurRadius: 14,
                  spreadRadius: 0,
                ),
              ],
            ),
          ),
          Container(
            width: size - 6,
            height: size - 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0C100F).withValues(alpha: 0.92),
              border: Border.all(
                color: accent.withValues(alpha: 0.85),
                width: 1.4,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  code,
                  style: TextStyle(
                    color: accent,
                    fontSize: compact ? 13 : 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 7,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    height: 1,
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

class _StatCapsule extends StatelessWidget {
  const _StatCapsule({
    required this.label,
    required this.value,
    required this.accent,
    this.mono = false,
  });

  final String label;
  final String value;
  final Color accent;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: accent.withValues(alpha: 0.75),
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textPrimary.withValues(alpha: 0.92),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: mono ? 0.3 : -0.1,
              fontFamily: mono ? 'Courier' : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscHero extends StatelessWidget {
  const _DiscHero({
    required this.item,
    required this.size,
    required this.animateVisual,
    required this.useDiscTexture,
  });

  final SoundMemory item;
  final double size;
  final bool animateVisual;
  final bool useDiscTexture;

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
                const ColoredBox(color: Color(0xFFF5F7F4)),
                Opacity(
                  opacity: 0.58,
                  child: Image.asset(
                    discTextureFor(item.visualSeed),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                ColoredBox(color: Colors.black.withValues(alpha: 0.22)),
                RarityHoloOverlay(
                  rarity: item.discRarity,
                  intensityScale: 1.2,
                  enabled: animateVisual,
                ),
              ],
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                SoundVisualCanvas(
                  seed: item.visualSeed,
                  mode: animateVisual
                      ? SoundVisualMode.playback
                      : SoundVisualMode.complete,
                  active: animateVisual,
                  dark: true,
                ),
                RarityHoloOverlay(
                  rarity: item.discRarity,
                  intensityScale: 1.0,
                  enabled: animateVisual,
                ),
              ],
            ),
    );

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
            // Soft ground glow under disc
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
            // Specular disc highlight
            IgnorePointer(
              child: Align(
                alignment: const Alignment(-0.45, -0.55),
                child: Container(
                  width: size * 0.38,
                  height: size * 0.22,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(size),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.28),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
