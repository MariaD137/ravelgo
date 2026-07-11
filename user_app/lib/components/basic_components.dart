import 'package:flutter/material.dart';
class AppColors {
  static const primary = Color(0xFFFFD500);
  static const background = Color(0xFFF6F6F6);
  static const border = Color(0xFFE0E0E0);
  static const textSecondary = Colors.black54;
}
class AppComponents {
  /// ================= HEADER =================
  static Widget header(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// ================= CARD =================
  static BoxDecoration cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 6),
      ],
    );
  }

  /// ================= DIVIDER =================
  static Widget divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppColors.border,
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ]
                ],
              ),
            ),
            if (done)
              const Icon(Icons.check_circle,
                  color: Colors.green, size: 18),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }

  /// ================= SEARCH FIELD =================
  static Widget searchField(String hint) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          border: InputBorder.none,
        ),
      ),
    );
  }

  /// ================= INPUT FIELD =================
  static Widget inputField({
    String? value,
    String? hint,
  }) {
    return TextField(
      controller:
      value != null ? TextEditingController(text: value) : null,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  /// ================= LABEL =================
  static Widget label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  /// ================= UPLOAD BOX =================
  static Widget uploadBox() {
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
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.image_outlined),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "Please upload square images",
              style: TextStyle(fontSize: 12),
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
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600),
        ),
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
          backgroundColor: const Color(0xFFE6D89C),
        ),
        child: Text(text),
      ),
    );
  }

  /// ================= BOTTOM NAV =================
  static Widget bottomNav(int index) {
    return BottomNavigationBar(
      currentIndex: index,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: Colors.grey,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: "Home"),
        BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: "Services"),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: "Rides"),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: "Account"),
      ],
    );
  }
  /// ================= SectionTitle =================
  static Widget SectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
    );
  }
  /// ================= Item =================
  static Widget Item(
      String title, {
        bool done = false,
        VoidCallback? onTap,
      }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 15),
              ),
            ),

            if (done)
              const Icon(Icons.check_circle,
                  color: Colors.green, size: 18),

            const SizedBox(width: 6),

            const Icon(Icons.chevron_right, size: 18),
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
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
          "Make sure your photos are readable and unobstructed.",
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
          ),
          child: Row(
            children: [
              Container(width: 60, height: 60, color: Colors.grey.shade200),
              const SizedBox(width: 10),
              const Expanded(
                child: Text("Please upload square images"),
              ),
            ],
          ),
        ),
      ],
    );
  }

}