import 'package:flutter/material.dart';
import 'package:ravelgo_driver/views/Driver_Portal/side_menu_driver.dart';

class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({Key? key}) : super(key: key);

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  String selectedMonth = "April 2025";
  String selectedPayment = "Payment method";

  bool hasTrips = true; // Change to false to show empty state

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SideMenuDriver(initialSelectedItem: "My Trips",),
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
                "My Trips",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: 20),

              /// FILTER ROW
              Row(
                children: [
                  Expanded(child: _filterBox(selectedMonth)),
                  const SizedBox(width: 14),
                  Expanded(child: _filterBox(selectedPayment)),
                ],
              ),

              const SizedBox(height: 14),

              /// DOWNLOAD BUTTON
              if (hasTrips)
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text("Download"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),

              const SizedBox(height: 28),

              if (hasTrips) ...[
                _summaryRow("Total sum:", "#200,000"),
                _summaryRow("Total cancelation fee:", "#20,000"),
                _summaryRow("Number of trips:", "15"),
                _summaryRow("Total Distance:", "200km"),

                const SizedBox(height: 24),

                _tripCard(),
                const SizedBox(height: 20),
                _tripCard(),
              ] else ...[
                const SizedBox(height: 40),
                _emptyState(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterBox(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: Text(text)),
          const Icon(Icons.keyboard_arrow_down),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label,
              style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _tripCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFFFD500), width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            children: const [
              Icon(Icons.location_on, color: Colors.green),
              SizedBox(width: 8),
              Text("Denco court 1",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),

          const SizedBox(height: 8),

          Row(
            children: const [
              Icon(Icons.calendar_today_outlined, size: 18),
              SizedBox(width: 8),
              Text("29.04.2024 16:20"),
            ],
          ),

          const SizedBox(height: 14),

          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD500),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text("Finished",
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),

          const SizedBox(height: 18),

          const Text("Mode of payment",
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text("Cash"),
          const SizedBox(height: 6),
          const Text("29.04.2024 16:20"),

          const SizedBox(height: 16),

          const Text("Distance",
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text("20km"),

          const SizedBox(height: 20),

          const Align(
            alignment: Alignment.bottomRight,
            child: Text(
              "#5000.00",
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B5A00)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Column(
      children: const [
        Icon(Icons.directions_car_filled_outlined, size: 60),
        SizedBox(height: 16),
        Text(
          "No Trips found",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8),
        Text(
          "Your most recent trips will appear here",
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }
}