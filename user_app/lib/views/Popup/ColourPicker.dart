import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

Future<String?> showColorPickerPopup(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final colors = [
        {"label": "Beige", "color": Color(0xFFF0E1C6)},
        {"label": "Black", "color": Colors.black},
        {"label": "Blue", "color": Color(0xFF1565C0)},
        {"label": "Brown", "color": Color(0xFF754C24)},
        {"label": "Dark gray", "color": Colors.black54},
        {"label": "Gold", "color": Color(0xFFD4AF37)},
        {"label": "Gray", "color": Color(0xFFE0E0E0)},
        {"label": "Green", "color": Color(0xFF2E7D32)},
        {"label": "Light blue", "color": Color(0xFFBFCBFF)},
        {"label": "Orange", "color": Color(0xFFF1A100)},
        {"label": "Pink", "color": Color(0xFFFF4FCF)},
      ];

      return Padding(
        padding: EdgeInsets.only(top: 12, bottom: 20),
        child: ListView.separated(
          itemCount: colors.length,
          separatorBuilder: (_, __) => Divider(height: 1),
          itemBuilder: (_, index) {
            final item = colors[index];

            return ListTile(
              leading: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: item["color"] as Color,
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(
                item["label"] as String,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              onTap: () => Navigator.pop(ctx, item["label"]),
            );
          },
        ),
      );
    },
  );
}