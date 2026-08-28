import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/components/basic_components.dart';
import 'package:ravelgo_user_app/views/Services/BrandModelPage.dart';

class BrandPage extends StatelessWidget {
  const BrandPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),

      body: SafeArea(
        child: Column(
          children: [

            /// HEADER
            AppComponents.header(context, "Brand"),

            /// CONTENT
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 2,
                  child: Column(
                    children: [

                      /// SEARCH
                      AppComponents.searchField("Search brand"),
                      AppComponents.divider(),

                      /// LIST
                      Expanded(
                        child: ListView(
                          children: [

                            AppComponents.SectionTitle("A"),
                            _item(context, "AB MOTORS"),
                            _item(context, "Acura"),
                            _item(context, "Adam"),

                            AppComponents.SectionTitle("B"),
                            _item(context, "B52"),
                            _item(context, "BAW"),

                            AppComponents.SectionTitle("C"),
                            _item(context, "C50"),
                            _item(context, "CAB"),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔥 REUSABLE ITEM (CLEAN FLOW)
  Widget _item(BuildContext context, String brand) {
    return AppComponents.Item(
      brand,
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BrandModelPage(brand: brand),
          ),
        );

        /// RETURN RESULT BACK
        if (result != null) {
          Navigator.pop(context, result);
        }
      },
    );
  }
}