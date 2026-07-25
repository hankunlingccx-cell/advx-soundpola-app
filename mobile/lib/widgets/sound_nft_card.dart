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
/// 保持贴图／可视化在全站的一致性（见 first.md §18.6）。
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
          _buildVisual(visualSize),
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
          ..._buildMetaRows(),
          if (variant == SoundNftCardVariant.share) ...[
            SizedBox(height: compact ? AppSpacing.tight : AppSpacing.item),
            Text(
              'SoundPola',
              style: TextStyle(
                color: _accent.withValues(alpha: 0.55),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildMetaRows() {
    if (variant == SoundNftCardVariant.share) {
      return [
        _metaRow('地点', item.locationLabel),
        _metaRow('日期', formatRecordedAt(item.recordedAt)),
      ];
    }
    return [
      _metaRow('声片编号', item.discId ?? '—'),
      _metaRow('数字资产编号', _abbreviate(item.assetId)),
      _metaRow(
        '上链时间',
        item.chainedAt != null ? formatRecordedAt(item.chainedAt!) : '—',
      ),
    ];
  }

  Widget _buildVisual(double size) {
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
                const ColoredBox(color: Colors.white),
                Opacity(
                  opacity: 0.5,
                  child: Image.asset(
                    discTextureFor(item.visualSeed),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
                RarityHoloOverlay(
                  rarity: item.discRarity,
                  intensityScale: 1.15,
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
                ),
              ],
            ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: SsrAuraLayer(
        size: size,
        enabled: _isSsr,
        playing: animateVisual,
        energy: 0.45,
        intensity: 1,
        child: Stack(
          alignment: Alignment.center,
          children: [
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
