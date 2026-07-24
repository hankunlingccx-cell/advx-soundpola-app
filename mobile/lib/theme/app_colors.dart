import 'package:flutter/material.dart';

/// designstyle.md V2.0 §2 — 仅深色主题
abstract final class AppColors {
  static const bgPrimary = Color(0xFF000000);
  static const bgElevated = Color(0xFF070A09);
  static const surface1 = Color(0xFF0D1110);
  static const surface2 = Color(0xFF141A18);
  static const border = Color(0xFF26302D);
  static const borderSubtle = Color(0xFF19201E);

  static const textPrimary = Color(0xFFF4F7F6);
  static const textSecondary = Color(0xFFA5AFAC);
  static const textTertiary = Color(0xFF68736F);

  static const accent = Color(0xFF63E0CB);
  static const accentSoft = Color(0xFF9AEBDD);
  static const accentDark = Color(0xFF2E7D70);
  static const accentOn = Color(0xFF04110E);
  static const accentHighlight = Color(0xFFD8FFF8);
  static const bottomNav = Color(0xFF090C0B);

  static const success = Color(0xFF63E0CB);
  static const warning = Color(0xFFF2C879);
  static const error = Color(0xFFFF6B72);
  static const info = Color(0xFF8AB8FF);

  // Legacy aliases → V2 (screens gradually migrate)
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
  static const white = surface2;

  static const darkCanvas = bgPrimary;
  static const darkSurface = surface1;
  static const darkText = textPrimary;
  static const darkSecondary = textSecondary;
}
