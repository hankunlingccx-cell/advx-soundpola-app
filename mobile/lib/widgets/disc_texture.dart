import '../data/disc_rarity.dart';

/// 声片贴图：按稀有度等级固定映射（N／R／SR／SSR），全站复用。
const discTextureByRarity = {
  DiscRarity.n: 'assets/disc_textures/disc_n.png',
  DiscRarity.r: 'assets/disc_textures/disc_r.png',
  DiscRarity.sr: 'assets/disc_textures/disc_sr.png',
  DiscRarity.ssr: 'assets/disc_textures/disc_ssr.png',
};

/// 稀有度未揭晓时回退到 N 档贴图。
String discTextureFor(DiscRarity? rarity) =>
    discTextureByRarity[rarity ?? DiscRarity.n]!;
