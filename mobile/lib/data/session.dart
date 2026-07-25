import 'disc_rarity.dart';
import '../visual/audio_feature_timeline.dart';

/// 录音完成后、保存 Draft 前的临时会话数据。
class RecordingSession {
  RecordingSession._();

  static String? audioPath;
  static int durationSec = 0;
  static int visualSeed = 0;
  static AudioFeatureTimeline? featureTimeline;
  /// True when audio came from local file import (not live mic).
  static bool fromImport = false;
  static String? suggestedTitle;

  static void set({
    required String path,
    required int duration,
    int? seed,
    AudioFeatureTimeline? timeline,
    bool imported = false,
    String? titleHint,
  }) {
    audioPath = path;
    durationSec = duration;
    if (seed != null) visualSeed = seed;
    if (timeline != null) featureTimeline = timeline;
    fromImport = imported;
    if (titleHint != null) suggestedTitle = titleHint;
  }

  static void clear() {
    audioPath = null;
    durationSec = 0;
    visualSeed = 0;
    featureTimeline = null;
    fromImport = false;
    suggestedTitle = null;
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
