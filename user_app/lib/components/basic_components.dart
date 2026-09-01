import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
export 'package:ravelgo_user_app/theme/app_theme.dart' show AppColors;

class AppComponents {
  /// ================= HEADER =================
  static Widget header(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            title,
            style: AppTypography.title.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  /// ================= CARD =================
  static BoxDecoration cardDecoration() {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      border: Border.all(color: AppColors.border),
    );
  }

  /// ================= DIVIDER =================
  static Widget divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Divider(height: 1, thickness: 1, color: AppColors.divider),
    );
  }

  /// ================= LIST TILE =================
  static Widget tile({
    required String title,
    String? subtitle,
    bool done = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.base),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.cardTitle.copyWith(color: AppColors.textPrimary),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (done)
              const Icon(Icons.check_circle, color: AppColors.success, size: 18),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  /// ================= SEARCH FIELD =================
  static Widget searchField(String hint) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: TextField(
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
          border: InputBorder.none,
        ),
      ),
    );
  }

  /// ================= INPUT FIELD =================
  static Widget inputField({String? value, String? hint}) {
    return TextField(
      controller: value != null ? TextEditingController(text: value) : null,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg - 6,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  /// ================= LABEL =================
  static Widget label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs + 2),
      child: Text(text, style: AppTypography.body.copyWith(color: AppColors.textPrimary)),
    );
  }

  /// ================= UPLOAD BOX =================
  static Widget uploadBox() {
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
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: const Icon(Icons.image_outlined, color: AppColors.textSecondary),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              "Please upload square images",
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  /// ================= PRIMARY BUTTON =================
  static Widget primaryButton({
    required String text,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        child: Text(text),
      ),
    );
  }

  /// ================= DISABLED BUTTON =================
  static Widget disabledButton(String text) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.disabled,
          foregroundColor: AppColors.textMuted,
        ),
        child: Text(text),
      ),
    );
  }

  /// ================= BOTTOM NAV =================
  static Widget bottomNav(int index) {
    return BottomNavigationBar(
      currentIndex: index,
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textMuted,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: "Home"),
        BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: "Services"),
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_today),
          label: "Rides",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          label: "Account",
        ),
      ],
    );
  }

  /// ================= SectionTitle =================
  static Widget SectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: AppTypography.title.copyWith(color: AppColors.textPrimary),
        ),
      ),
    );
  }

  /// ================= Item =================
  static Widget Item(String title, {bool done = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.base),
        child: Row(
          children: [
            Expanded(child: Text(title, style: AppTypography.body.copyWith(color: AppColors.textPrimary))),
            if (done)
              const Icon(Icons.check_circle, color: AppColors.success, size: 18),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  /// ================= UploadSection =================
  static Widget UploadSection(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.cardTitle.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          "Make sure your photos are readable and unobstructed.",
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.small),
            color: AppColors.surface,
          ),
          child: Row(
            children: [
              Container(width: 60, height: 60, color: AppColors.surfaceElevated),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Text(
                  "Please upload square images",
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
