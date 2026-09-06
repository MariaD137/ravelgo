import 'package:flutter/material.dart';

/// RavelGo design tokens - premium black-and-white surfaces, Turo-inspired.
/// White is the dominant background, black is the primary action color.
/// Semantic roles only: a color is used for what it means
/// (success/warning/error/disabled), never picked for decoration.
class AppColors {
  // Surfaces (white is dominant; elevated/variant are light neutral grays)
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFFF5F5F5);
  static const surfaceVariant = Color(0xFFF5F5F5);

  // Text
  static const textPrimary = Color(0xFF000000);
  static const textSecondary = Color(0xFF555555);
  static const textMuted = Color(0xFF888888);

  // Structure
  static const border = Color(0xFFE5E5E5);
  static const divider = Color(0xFFE5E5E5);

  // Primary action color (black, per the Turo-inspired direction)
  static const primary = Color(0xFF000000);
  static const primaryDark = Color(0xFF1A1A1A);
  static const primaryContainer = Color(0xFFF5F5F5);

  // Semantic
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFED6C02);
  static const error = Color(0xFFD32F2F);
  static const info = Color(0xFF1565C0);
  static const disabled = Color(0xFFE5E5E5);

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
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: "Roboto",
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
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
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3, color: AppColors.textPrimary),
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
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.disabled,
        disabledForegroundColor: AppColors.textMuted,
        elevation: 0,
        textStyle: AppTypography.button,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.primary),
        textStyle: AppTypography.button,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
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
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? AppColors.primary : AppColors.surface),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? AppColors.textSecondary : AppColors.disabled),
      trackOutlineColor: WidgetStateProperty.all(AppColors.border),
    ),
  );
}

class AppComponents {
  static Widget header(BuildContext context, String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(title, style: AppTypography.title.copyWith(color: AppColors.textPrimary))),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  static BoxDecoration cardDecoration({Color? borderColor}) {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      border: Border.all(color: borderColor ?? AppColors.border, width: borderColor != null ? 1.5 : 1),
    );
  }

  static Widget divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Divider(height: 1, thickness: 1, color: AppColors.divider),
    );
  }

  static Widget sectionTitle(String text, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.sm, AppSpacing.xs, AppSpacing.md),
      child: Row(
        children: [
          Expanded(child: Text(text, style: AppTypography.title.copyWith(color: AppColors.textPrimary))),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  static Widget tile({
    required String title,
    String? subtitle,
    IconData? leading,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.base),
        child: Row(
          children: [
            if (leading != null) ...[
              Icon(leading, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.cardTitle.copyWith(color: AppColors.textPrimary)),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(subtitle, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing else const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  static Widget primaryButton({required String text, required VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(onPressed: onPressed, child: Text(text)),
    );
  }

  static Widget outlineButton({required String text, required VoidCallback? onPressed, Color? color}) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color ?? AppColors.textPrimary,
          side: BorderSide(color: color ?? AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
        ),
        child: Text(text, style: AppTypography.button),
      ),
    );
  }

  static Widget badge(String text, {Color? color}) {
    final c = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(text, style: AppTypography.label.copyWith(color: c)),
    );
  }

  static Widget statCard(String label, String value, IconData icon, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: cardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(AppRadius.small)),
            child: Icon(icon, color: color ?? AppColors.textSecondary, size: 20),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(value, style: AppTypography.headline.copyWith(fontSize: 20, color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.xs / 2),
          Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  static Widget uploadPreview(String label) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: AppColors.border),
        color: AppColors.surface,
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(AppRadius.small)),
            child: const Icon(Icons.description_outlined, color: AppColors.textSecondary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary))),
        ],
      ),
    );
  }
}
