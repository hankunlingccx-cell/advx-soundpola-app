/// 声片贴图资源：Collection 跑道、分类播放主卡、横向堆叠共用，按 visualSeed 稳定映射。
const discTextureAssets = [
  'assets/disc_textures/disc_01.png',
  'assets/disc_textures/disc_02.png',
  'assets/disc_textures/disc_03.png',
  'assets/disc_textures/disc_04.png',
  'assets/disc_textures/disc_05.png',
  'assets/disc_textures/disc_06.png',
  'assets/disc_textures/disc_07.png',
];

String discTextureFor(int visualSeed) =>
    discTextureAssets[visualSeed.abs() % discTextureAssets.length];
