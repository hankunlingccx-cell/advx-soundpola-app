/// 模拟上链服务（NFC 写入完成后调用；失败时只重试上链，不重新写 NFC）。
/// NFT 元数据中的稀有度必须与实体声片一致。
class ChainService {
  ChainService._();
  static final ChainService instance = ChainService._();

  Future<String> submitAsset({
    required String soundId,
    required String discId,
    String? rarityCode,
    String? series,
  }) async {
    await Future.delayed(const Duration(milliseconds: 900));
    // rarity / series 写入模拟元数据上下文（真实链上应作为 tokenURI attributes）。
    final material =
        '$soundId|$discId|${rarityCode ?? ''}|${series ?? ''}';
    final hash = material.hashCode;
    return '0x${hash.toRadixString(16).padLeft(8, '0')}…';
  }
}
