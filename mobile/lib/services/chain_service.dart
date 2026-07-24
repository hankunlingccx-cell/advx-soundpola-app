/// 模拟上链服务（NFC 写入完成后调用；失败时只重试上链，不重新写 NFC）。
class ChainService {
  ChainService._();
  static final ChainService instance = ChainService._();

  Future<String> submitAsset({
    required String soundId,
    required String discId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 900));
    final hash = soundId.hashCode ^ discId.hashCode;
    return '0x${hash.toRadixString(16).padLeft(8, '0')}…';
  }
}
