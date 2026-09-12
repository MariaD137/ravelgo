import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views//Services/CarRentalScreen.dart';
import 'package:ravelgo_user_app/views/Delivery/SendPackageScreen.dart';
import 'package:ravelgo_user_app/views/TexiModule/FindRoute.dart';
import 'package:ravelgo_user_app/views/Stays/StaysScreen.dart';
import 'package:ravelgo_user_app/views/Eats/EatsScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class ServicesView extends StatelessWidget {
  const ServicesView({super.key});

  @override
  Widget build(BuildContext context) {
    // Each card image already has its own title, description, icon badge and
    // "go" arrow baked in by design, so these render as full self-contained
    // tiles with no separate label overlaid on top. `imageAsset` is null for
    // a service with no photography yet (Eats) — that tile renders as a
    // plain icon card instead of using a placeholder or borrowed image.
    final services = <(String, String?, IconData, VoidCallback)>[
      ('Ride', 'assets/card_ride.png', Icons.local_taxi,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => FindRouteScreen()))),
      ('Car Rentals', 'assets/card_car_rental.png', Icons.directions_car,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => CarRentalScreen()))),
      ('Delivery', 'assets/card_delivery.png', Icons.local_shipping,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SendPackageScreen()))),
      ('Short stay rentals', 'assets/card_short_stay.png', Icons.hotel,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaysScreen()))),
      ('Eats', null, Icons.restaurant,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EatsScreen()))),
    ];

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Text(
                "Our services",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                "Your ride, your way - anything delivered",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1,
                  children: [
                    for (final s in services)
                      Semantics(
                        button: true,
                        label: s.$1,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: s.$4,
                          child: s.$2 != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.asset(s.$2!, fit: BoxFit.cover),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(s.$3, color: AppColors.primaryDark, size: 32),
                                      const SizedBox(height: 8),
                                      Text(s.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
