/// 录音完成后、保存 Draft 前的临时会话数据。
class RecordingSession {
  RecordingSession._();

  static String? audioPath;
  static int durationSec = 0;

  static void set({required String path, required int duration}) {
    audioPath = path;
    durationSec = duration;
  }

  static void clear() {
    audioPath = null;
    durationSec = 0;
  }
}

/// Press 流程中检测到的 NFC 声片信息（检测 → 确认 → 写入）。
class PressSession {
  PressSession._();

  static String? tagIdHex;
  static String? discId;

  static void set({required String tagId, required String disc}) {
    tagIdHex = tagId;
    discId = disc;
  }

  static void clear() {
    tagIdHex = null;
    discId = null;
  }
}
