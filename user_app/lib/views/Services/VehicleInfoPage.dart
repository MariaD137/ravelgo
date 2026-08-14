import 'package:flutter/material.dart';
import 'package:ravelgo/Model/VehicleSelection.dart';
import 'package:ravelgo/components/basic_components.dart';
import 'package:ravelgo/views/Services/PhotoLicensePage.dart';

import 'BrandPage.dart';
import 'DriverLicensePage.dart';

class VehicleInfoPage extends StatefulWidget {
  const VehicleInfoPage({super.key});

  @override
  State<VehicleInfoPage> createState() => _VehicleInfoPageState();
}

class _VehicleInfoPageState extends State<VehicleInfoPage> {

  VehicleSelection? vehicle;

  /// FORMAT TEXT
  String get vehicleText {
    if (vehicle == null) return "Brands";
    return "${vehicle!.brand} ${vehicle!.model}, ${vehicle!.colour}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),

      body: SafeArea(
        child: Column(
          children: [

            /// HEADER
            AppComponents.header(context, "Vehicle Info"),

            /// CARD
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: AppComponents.cardDecoration(),
                child: Column(
                  children: [

                    /// BRAND / MODEL / COLOR
                    AppComponents.Item(
                      vehicleText,
                      done: vehicle != null,
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BrandPage(),
                          ),
                        );

                        if (result != null) {
                          setState(() {
                            vehicle = result;
                          });
                        }
                      },
                    ),

                    AppComponents.divider(),

                    /// DRIVER LICENSE
                    AppComponents.Item(
                      "Driver licence",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DriverLicensePage(),
                          ),
                        );
                      },
                    ),

                    AppComponents.divider(),

                    /// PHOTO LICENSE
                    AppComponents.Item(
                      "Photo with driver license",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PhotoLicensePage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            /// DONE BUTTON
            Padding(
              padding: const EdgeInsets.all(16),
              child: vehicle != null
                  ? AppComponents.primaryButton(
                text: "Done",
                onPressed: () {},
              )
                  : AppComponents.disabledButton("Done"),
            ),
          ],
        ),
      ),
    );
  }
}