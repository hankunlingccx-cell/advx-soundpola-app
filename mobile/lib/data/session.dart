import 'disc_rarity.dart';

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

/// Press 流程中检测到的 NFC 声片信息（检测 → 揭晓 → 确认 → 写入）。
class PressSession {
  PressSession._();

  static String? tagIdHex;
  static String? discId;
  static DiscRarity? rarity;
  static String? series;
  static String? factorySignature;
  static bool rarityRevealed = false;
  static bool factoryDemo = false;

  static void set({
    required String tagId,
    required String disc,
    required DiscRarity discRarity,
    required String discSeries,
    required String signature,
    bool demo = false,
  }) {
    tagIdHex = tagId;
    discId = disc;
    rarity = discRarity;
    series = discSeries;
    factorySignature = signature;
    factoryDemo = demo;
    rarityRevealed = false;
  }

  static void markRevealed() => rarityRevealed = true;

  static void clear() {
    tagIdHex = null;
    discId = null;
    rarity = null;
    series = null;
    factorySignature = null;
    rarityRevealed = false;
    factoryDemo = false;
  }
}
