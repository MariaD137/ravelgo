import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views/Driver_Portal/side_menu_driver.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class VehicleListScreen extends StatelessWidget {
  const VehicleListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SideMenuDriver(initialSelectedItem: "Vehicles",),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              /// HEADER
              Row(
                children: [
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openDrawer(),
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 6),
                          ],
                        ),
                        child: const CircleAvatar(
                          backgroundColor: Colors.white,
                          child: Icon(Icons.menu, color: Colors.black),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Image.asset(
                    "assets/ravel_go_driver_badge.png",
                    height: 28,
                  ),
                ],
              ),

              const SizedBox(height: 28),

              /// TITLE
              const Text(
                "Vehicles",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: 8),

              const Text(
                "This section provides an overview of your vehicles.",
                style: TextStyle(color: Colors.black54),
              ),

              const SizedBox(height: 20),

              /// ADD NEW VEHICLE BUTTON
              ElevatedButton(
                onPressed: () {
                  // Navigate to Add Vehicle Screen
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  "Add new vehicle",
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),

              const SizedBox(height: 30),

              /// VEHICLE LIST
              _vehicleCard(
                model: "Kia Rio (2022)",
                plate: "AGL438JK",
              ),

              const SizedBox(height: 18),

              _vehicleCard(
                model: "Kia Rio (2022)",
                plate: "AGL438JK",
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vehicleCard({
    required String model,
    required String plate,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [

          /// MODEL ROW
          Row(
            children: [
              const Text(
                "Model",
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                model,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Divider(color: Colors.grey.shade400),

          const SizedBox(height: 14),

          /// LICENSE PLATE ROW
          Row(
            children: [
              const Text(
                "License Plate",
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                plate,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.green),
              ),
            ],
          ),
        ],
      ),
    );
  }
}