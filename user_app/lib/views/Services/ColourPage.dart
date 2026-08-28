import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/components/basic_components.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class ColourPage extends StatelessWidget {
  const ColourPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      body: SafeArea(
        child: Column(
          children: [

            /// HEADER
            AppComponents.header(context, "Colour"),

            /// CONTENT
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 2,
                  child: ListView.separated(
                    itemCount: _colors.length,
                    separatorBuilder: (_, __) => _divider(),
                    itemBuilder: (context, index) {
                      final item = _colors[index];

                      return _item(
                        context,
                        item['name'] as String,
                        item['color'] as Color,
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// COLOR ITEM
  Widget _item(BuildContext context, String title, Color color) {
    return InkWell(
      onTap: () {
        /// 🔥 RETURN COLOUR ONLY
        Navigator.pop(context, title);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [

            /// COLOR DOT
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),

            const SizedBox(width: 12),

            /// TITLE
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// INDENTED DIVIDER (MATCH DESIGN)
  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.only(left: 44),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppColors.border,
      ),
    );
  }
}

/// COLOR DATA
final List<Map<String, dynamic>> _colors = [
  {"name": "Beige", "color": Color(0xFFE5D3B3)},
  {"name": "Black", "color": Colors.black},
  {"name": "Blue", "color": Color(0xFF1565C0)},
  {"name": "Brown", "color": Color(0xFF8B5A2B)},
  {"name": "Dark gray", "color": Colors.black54},
  {"name": "Gold", "color": Color(0xFF665600)},
  {"name": "Gray", "color": Color(0xFFE0E0E0)},
  {"name": "Green", "color": Color(0xFF2E7D32)},
  {"name": "Light blue", "color": Color(0xFF9FA8DA)},
  {"name": "Orange", "color": Color(0xFFED6C02)},
  {"name": "Pink", "color": Color(0xFFE843C4)},
];