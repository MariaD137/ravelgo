import 'package:flutter/material.dart';
import 'package:ravelgo/Model/VehicleSelection.dart';
import 'package:ravelgo/components/basic_components.dart';
import 'package:ravelgo/views/Services/ColourPage.dart';

class BrandModelPage extends StatelessWidget {
  final String brand;

  const BrandModelPage({
    super.key,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      body: SafeArea(
        child: Column(
          children: [

            /// HEADER
            AppComponents.header(context, brand), // show selected brand

            /// CONTENT
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      /// SEARCH
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.search, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  hintText: "Search model",
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      /// UNDERLINE
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.grey.shade300,
                        ),
                      ),

                      /// LIST
                      Expanded(
                        child: ListView(
                          children: [

                            /// SECTION
                            const Padding(
                              padding:
                              EdgeInsets.fromLTRB(14, 12, 14, 6),
                              child: Text(
                                "A",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                            _item(context, "AB 110"),
                            AppComponents.divider(),

                            _item(context, "AB 150"),
                            AppComponents.divider(),

                            _item(context, "AB 170"),
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

  /// 🔥 REUSABLE MODEL ITEM
  Widget _item(BuildContext context, String model) {
    return AppComponents.Item(
      model,
      onTap: () async {

        /// PUSH COLOUR PAGE
        final colour = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ColourPage(),
          ),
        );

        /// RETURN FULL DATA
        if (colour != null) {
          Navigator.pop(
            context,
            VehicleSelection(
              brand: brand,
              model: model,
              colour: colour,
            ),
          );
        }
      },
    );
  }
}