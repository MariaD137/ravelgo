import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user_app/components/LocationService.dart';
import 'package:ravelgo_user_app/components/SafeGoogleMap.dart';
import 'package:ravelgo_user_app/views/TexiModule/FindDriverScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class SelectRide extends StatefulWidget {
  /// Destination chosen on the previous screen (route search); shown in the
  /// search bar so the selection visibly carries through the flow.
  final String? destination;
  const SelectRide({super.key, this.destination});

  @override
  State<SelectRide> createState() => _SelectRideState();
}

class _SelectRideState extends State<SelectRide> {
  GoogleMapController? mapController;
  // Cash is no longer a RavelGo payment method — rides are paid by card or the
  // RavelGo wallet, both handled by the backend so the platform can take its
  // commission and pay the driver.
  String _paymentMethod = 'Card';
  DateTime? _scheduledFor;

  /// Recenter the map on the device's real location (geolocator).
  Future<void> _recenterOnMe() async {
    final position = await LocationService.getCurrentLocation();
    if (position == null || mapController == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get your location - check permissions')),
        );
      }
      return;
    }
    mapController!.animateCamera(CameraUpdate.newLatLng(
      LatLng(position.latitude, position.longitude),
    ));
  }

  Future<void> _pickPaymentMethod() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Pay with', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final m in const ['Card', 'RavelGo Wallet'])
              ListTile(
                title: Text(m),
                trailing: m == _paymentMethod
                    ? const Icon(Icons.check, color: AppColors.success)
                    : null,
                onTap: () => Navigator.pop(context, m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result != null) setState(() => _paymentMethod = result);
  }

  /// Schedule this ride for later (LOCAL STATE ONLY until the trips backend
  /// accepts scheduled requests).
  Future<void> _scheduleRide() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null || !mounted) return;
    setState(() {
      _scheduledFor = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Ride scheduled for ${_scheduledFor!.day}/${_scheduledFor!.month} at ${time.format(context)}'),
    ));
  }

  final LatLng _center = const LatLng(6.6018, 3.3515); // Sample: Lagos

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          SafeGoogleMap(
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
              backgroundColor: AppColors.surface,
              child: IconButton(
                icon: const Icon(Icons.my_location),
                onPressed: _recenterOnMe,
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
                  color: AppColors.surface,
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
                            backgroundColor: AppColors.surface,
                            foregroundColor: AppColors.textPrimary,
                            elevation: 0,
                            side: const BorderSide(color: AppColors.border),
                          ),
                          icon: const Icon(Icons.credit_card, size: 20),
                          label: Text(_paymentMethod),
                          onPressed: _pickPaymentMethod,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
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
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => FindDriverScreen(
                                    destination: widget.destination,
                                    paymentMethod: _paymentMethod,
                                  ),
                                ),
                              );
                            },
                            child: const Text("Select Just ride", style: TextStyle(color: AppColors.textPrimary)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.textPrimary,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(12),
                          ),
                          onPressed: _scheduleRide,
                          child: const Icon(Icons.calendar_today, color: AppColors.surface, size: 20),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children:  [
          IconButton(
            icon: const Icon(Icons.arrow_back,color: AppColors.textPrimary,),
            onPressed: () => Navigator.pop(context),
          ),
          SizedBox(width: 8),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: widget.destination ?? "Where to?",
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
        border: isSelected ? Border.all(color: AppColors.success, style: BorderStyle.solid, width: 1.5, strokeAlign: BorderSide.strokeAlignOutside) : Border.all(color: AppColors.textMuted, style: BorderStyle.solid, width: 1, strokeAlign: BorderSide.strokeAlignOutside) ,
        borderRadius: BorderRadius.circular(12),
        color: AppColors.surface,
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
              const Text("#2444", style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          )
        ],
      ),
    );
  }
}