abstract final class AppRoutes {
  static const splash = '/splash';
  static const permission = '/permission';
  static const main = '/';
  static const recording = '/recording';
  static const result = '/result';
  static const draftDetail = '/draft/:id';
  static const pressMethod = '/press/method/:id';
  static const pressDetect = '/press/detect/:id';
  static const pressReveal = '/press/reveal/:id';
  static const pressConfirm = '/press/confirm/:id';
  static const pressProgress = '/press/progress/:id';
  static const pressDone = '/press/done/:id';
  /// 分类播放页：Category 声片浏览 + 播放 + 记忆 + 声片/数字资产信息一体化。
  /// 分类名走 path（Uri 编码，兼容中文），soundId 走 query。
  static const categoryPlay = '/collection/category/:categoryId';
  static const login = '/auth/login';
  static const register = '/auth/register';
  static const accountReady = '/auth/account-ready';
  static const privateKeyBackup = '/auth/private-key';
  static const account = '/account';
  static const pairDevice = '/account/pair-device';
  static const pairRing = '/account/pair-ring';
  static const myDevices = '/account/devices';
  static const deviceDetail = '/account/devices/:deviceId';
  static const serverSettings = '/settings/server';
  /// Sound Lab 声音实验室（底部第四 Tab；旁路路由 `/lab/sound` 仍可用）。
  static const soundLab = '/lab/sound';
  static const resolveContent = '/c/:contentId';
  /// Press 硬件写入路径（与手机 NFC 并存）。
  static const pressHardware = '/press/hardware/:id';

  static String mainTab(int tab) => '/?tab=$tab';
  static String resultPath(int duration) => '/result?duration=$duration';
  static String draftPath(String id) => '/draft/$id';
  static String loginPath({String? draftId}) =>
      draftId == null ? login : '$login?draftId=$draftId';
  static String pressProgressPath(String id, {bool chainOnly = false}) =>
      chainOnly ? '/press/progress/$id?chainOnly=1' : '/press/progress/$id';
  static String pressMethodPath(String id, {bool chainOnly = false}) =>
      chainOnly ? '/press/method/$id?chainOnly=1' : '/press/method/$id';
  static String pressDetectPath(String id) => '/press/detect/$id';
  static String pressRevealPath(String id) => '/press/reveal/$id';
  static String pressConfirmPath(String id) => '/press/confirm/$id';
  static String pressDonePath(String id) => '/press/done/$id';
  static String pressHardwarePath(String id) => '/press/hardware/$id';
  static String deviceDetailPath(String deviceId) =>
      '/account/devices/${Uri.encodeComponent(deviceId)}';
  static String contentPath(String contentId) => '/c/$contentId';

  /// 生成分类播放页路径；分类名用 [Uri.encodeComponent] 编码以兼容中文。
  /// 读取端直接用 `state.pathParameters`（已解码），不要再 decodeComponent。
  static String categoryPlayPath(String category, {String? soundId}) {
    final encodedCategory = Uri.encodeComponent(category);
    final query = (soundId != null && soundId.isNotEmpty)
        ? '?soundId=${Uri.encodeComponent(soundId)}'
        : '';
    return '/collection/category/$encodedCategory$query';
  }
}
