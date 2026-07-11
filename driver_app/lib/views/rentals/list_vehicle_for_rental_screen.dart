import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class ListVehicleForRentalScreen extends StatefulWidget {
  const ListVehicleForRentalScreen({super.key});

  @override
  State<ListVehicleForRentalScreen> createState() => _ListVehicleForRentalScreenState();
}

class _ListVehicleForRentalScreenState extends State<ListVehicleForRentalScreen> {
  bool _listed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Luxury Car Rental")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Partner with RavelGo to rent your car out directly through the app when you're not driving it.",
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            const TextField(decoration: InputDecoration(labelText: "Vehicle", border: OutlineInputBorder(), hintText: "Toyota Camry, Black")),
            const SizedBox(height: 16),
            const TextField(decoration: InputDecoration(labelText: "Daily rental rate (₦)", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            const TextField(decoration: InputDecoration(labelText: "Available pickup location", border: OutlineInputBorder())),
            const SizedBox(height: 20),
            AppComponents.uploadBox("Upload photos of the vehicle"),
            const SizedBox(height: 10),
            AppComponents.uploadBox("Upload proof of ownership / insurance"),
            const SizedBox(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("List this vehicle for rental"),
              subtitle: const Text("Visible to riders browsing Luxury Car Rental", style: TextStyle(fontSize: 12)),
              value: _listed,
              onChanged: (v) => setState(() => _listed = v),
            ),
            const SizedBox(height: 20),
            AppComponents.primaryButton(
              text: _listed ? "Update listing" : "Submit for review",
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Listing submitted for admin review")),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
