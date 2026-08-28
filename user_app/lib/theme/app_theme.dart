import 'package:flutter/material.dart';

/// Shared color palette for the rider app, matching the tokens used in
/// driver_app and admin_app's own AppColors so the three apps read as one
/// product instead of each screen picking its own near-duplicate shade.
class AppColors {
  static const primary = Color(0xFFFFD500);
  static const primaryDark = Color(0xFF665600);
  static const primaryTint = Color(0xFFFFF6CC);
  static const background = Color(0xFFF6F6F6);
  static const surface = Colors.white;
  static const border = Color(0xFFE0E0E0);
  static const textPrimary = Colors.black87;
  static const textSecondary = Colors.black54;
  static const success = Color(0xFF2E7D32);
  static const danger = Color(0xFFD32F2F);
  static const warning = Color(0xFFED6C02);
  static const info = Color(0xFF1565C0);
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      brightness: Brightness.light,
    ),
    fontFamily: "Roboto",
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    ),
  );
}
