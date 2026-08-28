import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFFEF4B37);
  static const primaryDark = Color(0xFFC23A28);
  static const background = Color(0xFFF6F6F6);
  static const border = Color(0xFFE0E0E0);
  static const textSecondary = Colors.black54;
  static const success = Color(0xFF2E7D32);
  static const danger = Color(0xFFD32F2F);
  static const online = Color(0xFF2E7D32);
  static const offline = Color(0xFF9E9E9E);
}

class AppComponents {
  static Widget header(BuildContext context, String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  static BoxDecoration cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
    );
  }

  static Widget divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 14),
      child: Divider(height: 1, thickness: 1, color: AppColors.border),
    );
  }

  static Widget sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
    );
  }

  static Widget tile({
    required String title,
    String? subtitle,
    bool done = false,
    IconData? leading,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            if (leading != null) ...[
              Icon(leading, size: 20, color: Colors.black87),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ]
                ],
              ),
            ),
            if (done) const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }

  static Widget primaryButton({required String text, required VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }

  static Widget outlineButton({required String text, required VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }

  static Widget statChip(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  static Widget uploadBox(String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.upload_file_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
  }

  static Widget badge(String text, {Color? color}) {
    final c = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c == AppColors.primary ? AppColors.primaryDark : c)),
    );
  }
}
