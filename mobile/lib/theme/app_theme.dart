import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.canvasBg,
      colorScheme: ColorScheme.light(
        primary: AppColors.primary500,
        onPrimary: AppColors.ink950,
        primaryContainer: AppColors.primary100,
        onPrimaryContainer: AppColors.primary700,
        surface: AppColors.white,
        onSurface: AppColors.ink950,
        error: AppColors.error,
      ),
      dividerColor: AppColors.line200,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: AppColors.ink950,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AppColors.ink950,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: AppColors.ink800, height: 1.5),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.ink800, height: 1.5),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.ink800,
        ),
        labelSmall: TextStyle(fontSize: 12, color: AppColors.ink600),
      ),
    );
  }
}
