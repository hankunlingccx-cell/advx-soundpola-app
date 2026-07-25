/// Press 登录拦截后的任务恢复上下文。
class PressResume {
  PressResume._();

  static String? draftId;
  static String entry = 'press'; // press | mint | account

  static void set({
    required String id,
    String entryPoint = 'press',
  }) {
    draftId = id;
    entry = entryPoint;
  }

  static void clear() {
    draftId = null;
    entry = 'press';
  }

  static bool get hasPending => draftId != null && draftId!.isNotEmpty;
}
