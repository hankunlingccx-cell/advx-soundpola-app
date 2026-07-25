import 'package:flutter/material.dart';

/// designstyle.md — 深色展示空间 + 明亮精密仪器
abstract final class AppColors {
  /// 页面背景（衬托白色设备）
  static const bgPrimary = Color(0xFF050606);
  static const bgElevated = Color(0xFF0A0C0B);
  static const surface1 = Color(0xFF0D1110);
  static const surface2 = Color(0xFF141A18);
  static const border = Color(0xFF2A322F);
  static const borderSubtle = Color(0xFF1A201E);

  /// iOS 明亮精密仪器
  static const ceramic = Color(0xFFF2F3F1);
  static const highlight = Color(0xFFFFFFFF);
  static const silver = Color(0xFFC9CECC);
  static const silverDeep = Color(0xFFA8AFA8);
  static const structure = Color(0xFF969D9A);
  static const slotInterior = Color(0xFF242927);
  static const glassDark = Color(0xFF101312);
  static const ink = Color(0xFF111514);
  static const inkMuted = Color(0xFF747B78);

  /// 声卡浅色变体
  static const cardIvory = Color(0xFFF5F4F0);
  static const cardCool = Color(0xFFF0F3F4);
  static const cardSilver = Color(0xFFE8ECEB);

  /// 兼容旧命名
  static const device = glassDark;
  static const graphite = Color(0xFF101614);

  static const textPrimary = Color(0xFFF2F5F4);
  static const textSecondary = Color(0xFFA5AFAC);
  static const textTertiary = Color(0xFF747B78);

  static const accent = Color(0xFF63E0CB);
  static const accentSoft = Color(0xFF9AEBDD);
  static const accentDark = Color(0xFF2E7D70);
  static const accentOn = Color(0xFF04110E);
  static const accentHighlight = Color(0xFFD8FFF8);
  static const bottomNav = Color(0x00000000);

  static const success = Color(0xFF63E0CB);
  static const warning = Color(0xFFF2C879);
  static const error = Color(0xFFFF6B72);
  static const info = Color(0xFF8AB8FF);

  static const primary500 = accent;
  static const primary600 = Color(0xFF3FC7B2);
  static const primary700 = accentDark;
  static const primary300 = accentSoft;
  static const primary100 = Color(0xFF1A2E2A);
  static const primary50 = surface1;

  static const ink950 = textPrimary;
  static const ink800 = textSecondary;
  static const ink600 = textSecondary;
  static const ink400 = textTertiary;
  static const line200 = border;
  static const surface100 = surface1;
  static const canvasBg = bgPrimary;
  static const white = highlight;

  static const darkCanvas = bgPrimary;
  static const darkSurface = surface1;
  static const darkText = textPrimary;
  static const darkSecondary = textSecondary;
}
