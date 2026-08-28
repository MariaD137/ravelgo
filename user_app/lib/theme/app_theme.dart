import 'package:flutter/material.dart';

/// RavelGo design tokens - matte charcoal/graphite surfaces with a
/// restrained coral accent. Semantic roles only: a color is used for what
/// it means (success/warning/error/disabled), never picked for decoration.
/// Kept in sync with driver_app and admin_app's own AppColors so the three
/// apps read as one product instead of each screen picking its own shade.
class AppColors {
  // Surfaces (darkest to lightest)
  static const background = Color(0xFF121214);
  static const surface = Color(0xFF1B1C1F);
  static const surfaceElevated = Color(0xFF232428);
  static const surfaceVariant = Color(0xFF2A2B30);

  // Text
  static const textPrimary = Color(0xFFF2F1EF);
  static const textSecondary = Color(0xFFA8A8AD);
  static const textMuted = Color(0xFF6E6E74);

  // Structure
  static const border = Color(0xFF33343A);
  static const divider = Color(0xFF2A2B30);

  // Brand accent
  static const primary = Color(0xFFEF4B37);
  static const primaryDark = Color(0xFFC23A28);
  static const primaryTint = Color(0xFF3A2620);
  static const primaryContainer = Color(0xFF3A2620);

  // Semantic
  static const success = Color(0xFF4CAF7D);
  static const warning = Color(0xFFD9A441);
  static const error = Color(0xFFE0544A);
  static const info = Color(0xFF5B8DEF);
  static const disabled = Color(0xFF4A4B52);

  // Legacy aliases kept for screens not yet migrated off these names.
  static const danger = error;
}

/// 4/8-based spacing scale. Not applied mechanically everywhere - use
/// whichever step reads right for the given gap.
class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const base = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 40.0;
  static const huge = 48.0;
}

/// Shape scale shared by cards, buttons, inputs, sheets, chips.
class AppRadius {
  static const small = 8.0;
  static const medium = 12.0;
  static const large = 20.0;
  static const pill = 999.0;
}

/// Type scale. Colors are intentionally omitted here (callers set color
/// per-context via AppColors) except where a role always means one thing.
class AppTypography {
  static const display = TextStyle(fontSize: 32, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.5);
  static const headline = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.25);
  static const title = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3);
  static const cardTitle = TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3);
  static const body = TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.45);
  static const bodySmall = TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.4);
  static const label = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3);
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.3);
  static const button = TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.2);
  static const navigation = TextStyle(fontSize: 11, fontWeight: FontWeight.w500, height: 1.2);
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: "Roboto",
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primary,
      surface: AppColors.surface,
      error: AppColors.error,
    ),
    textTheme: const TextTheme(
      displayLarge: AppTypography.display,
      headlineLarge: AppTypography.headline,
      titleLarge: AppTypography.title,
      titleMedium: AppTypography.cardTitle,
      bodyLarge: AppTypography.body,
      bodyMedium: AppTypography.bodySmall,
      labelLarge: AppTypography.button,
      labelSmall: AppTypography.caption,
    ).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3, color: AppColors.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        disabledBackgroundColor: AppColors.disabled,
        elevation: 0,
        textStyle: AppTypography.button,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        textStyle: AppTypography.button,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceElevated,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textMuted,
      type: BottomNavigationBarType.fixed,
    ),
    iconTheme: const IconThemeData(color: AppColors.textSecondary),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
    ),
  );
}
