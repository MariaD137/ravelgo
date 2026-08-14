import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo/views/TexiModule/FindDriverScreen.dart';

class SelectRide extends StatefulWidget {
  const SelectRide({super.key});

  @override
  State<SelectRide> createState() => _SelectRideState();
}

class _SelectRideState extends State<SelectRide> {
  GoogleMapController? mapController;

  final LatLng _center = const LatLng(6.6018, 3.3515); // Sample: Lagos

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            onMapCreated: (controller) => mapController = controller,
            initialCameraPosition: CameraPosition(
              target: _center,
              zoom: 14.0,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
          ),

          // Top bar with back, location search, and add
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildSearchBar(),
            ),
          ),

          // Location button
          Positioned(
            right: 16,
            bottom: 280,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.my_location),
                onPressed: () {},
              ),
            ),
          ),

          // Bottom draggable sheet
          DraggableScrollableSheet(
            initialChildSize: 0.35,
            minChildSize: 0.35,
            maxChildSize: 0.65,
            builder: (_, controller) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.only(left: 12,top: 12,right: 12),
                child: Column(
                  children: [
                    const Text(
                      "Choose a ride",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: ListView(
                        controller: controller,
                        children: [
                          rideCard("Just ride", "#8000", "2min", "4", isSelected: true),
                          rideCard("EV", "#6000", "2min", "4"),
                          rideCard("Lite", "#5000", "4min", "3"),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Payment and Delivery Row
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            side: const BorderSide(color: Colors.black12),
                          ),
                          icon: Image.asset("assets/ic_cash_ride.png"),
                          label: const Text("Cash"),
                          onPressed: () {},
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: const Align(
                              alignment: Alignment.centerLeft,
                              child: Text("Pick up a delivery"),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Main CTA
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.yellow.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => FindDriverScreen()),
                              );
                            },
                            child: const Text("Select Just ride", style: TextStyle(color: Colors.black)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(12),
                          ),
                          onPressed: () {},
                          child: const Icon(Icons.calendar_today, color: Colors.white, size: 20),
                        )
                      ],
                    ),
                    const SizedBox(height: 0),
                  ],

                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children:  [
          IconButton(
            icon: const Icon(Icons.arrow_back,color: Colors.black,),
            onPressed: () => Navigator.pop(context),
          ),
          SizedBox(width: 8),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: "Denco court 1",
                border: InputBorder.none,
              ),
            ),
          ),
          Icon(Icons.add),
        ],
      ),
    );
  }

  Widget rideCard(String type, String fare, String eta, String seats, {bool isSelected = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12,left: 5,right: 5),
      decoration: BoxDecoration(
        border: isSelected ? Border.all(color: Colors.green, style: BorderStyle.solid, width: 1.5, strokeAlign: BorderSide.strokeAlignOutside) : Border.all(color: Colors.grey, style: BorderStyle.solid, width: 1, strokeAlign: BorderSide.strokeAlignOutside) ,
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.directions_car),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(eta),
                    const SizedBox(width: 8),
                    const Icon(Icons.person, size: 16),
                    Text(seats),
                  ],
                )
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fare, style: const TextStyle(fontWeight: FontWeight.w600)),
              const Text("#2444", style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }
}