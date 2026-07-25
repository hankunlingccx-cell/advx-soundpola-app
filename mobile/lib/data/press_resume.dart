/// Press 登录拦截后的任务恢复上下文。
class PressResume {
  PressResume._();

  static String? draftId;
  static bool chainOnly = false;
  static String entry = 'press'; // press | mint | account

  static void set({
    required String id,
    bool chainOnlyMode = false,
    String entryPoint = 'press',
  }) {
    draftId = id;
    chainOnly = chainOnlyMode;
    entry = entryPoint;
  }

  static void clear() {
    draftId = null;
    chainOnly = false;
    entry = 'press';
  }

  static bool get hasPending => draftId != null && draftId!.isNotEmpty;
}
