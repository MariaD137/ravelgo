import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user_app/components/SafeGoogleMap.dart';
import 'package:ravelgo_user_app/views/TexiModule/SearchDriverScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class FindDriverScreen extends StatefulWidget {
  const FindDriverScreen({super.key});

  @override
  State<FindDriverScreen> createState() => _FindDriverScreenState();
}

class _FindDriverScreenState extends State<FindDriverScreen> {
  GoogleMapController? _mapController;
  double offerAmount = 7000;
  double estimatedFare = 8000;
  bool autoAccept = false;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _loadMarkers();
  }

  Future<void> _loadMarkers() async {
    final markers = await _generateCarMarkers();
    setState(() {
      _markers = markers;
    });
  }

  Future<Set<Marker>> _generateCarMarkers() async {
    final icon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration.empty,
      'assets/car_marker.png',
    );
    return List.generate(
      10,
          (i) => Marker(
        markerId: MarkerId('car_\$i'),
        position: LatLng(6.524 + i * 0.001, 3.379 + i * 0.001),
        icon: icon,
      ),
    ).toSet();
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Ride scheduled for ${date.day}/${date.month} at ${time.format(context)}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeGoogleMap(
            onMapCreated: (controller) {
              setState(() {
                _mapController = controller;
              });
            },
            initialCameraPosition: const CameraPosition(
              target: LatLng(6.5244, 3.3792),
              zoom: 14,
            ),
            myLocationEnabled: true,
            zoomControlsEnabled: false,
            markers: _markers,
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildSearchBar(),
            ),
          ),

          Align(
            alignment: Alignment.bottomCenter,
            child: _buildTripInfoSheet(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(){
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

  Widget _buildTripInfoSheet(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: AppColors.border, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTripDetail(),
          const SizedBox(height: 12),
          _buildOfferSection(),
          const SizedBox(height: 12),
          _buildPaymentRow(),
          const SizedBox(height: 20),
          _buildFindDriverButton(),
          const SizedBox(height: 0),
        ],
      ),
    );
  }

  Widget _buildTripDetail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Your Trip", style: TextStyle(fontWeight: FontWeight.bold,fontSize: 18)),
        const SizedBox(height: 8),
        Row(
          children:  [
            Image.asset(
              'assets/ic_pickup.png',
              width: 24,
              height: 24,
            ),
            SizedBox(width: 8),
            Text("Denco court 1", style: TextStyle(fontWeight: FontWeight.normal,fontSize: 16)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children:  [
            Image.asset(
              'assets/ic_destination.png',
              width: 24,
              height: 24,
            ),
            SizedBox(width: 8),
            Text("Destiation ", style: TextStyle(fontWeight: FontWeight.normal,fontSize: 16)),
          ],
        ),
        const SizedBox(height: 15),
        Text("Estimated fare: NGN 8,000", style: TextStyle(color: Colors.brown,fontWeight: FontWeight.bold,fontSize: 14)),
      ],
    );
  }

  Widget _buildOfferSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Your offer", style: TextStyle(fontSize: 16)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text("NGN ${offerAmount.toStringAsFixed(0)}",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Spacer(),
            ElevatedButton(
              onPressed: offerAmount > 7000
                  ? () => setState(() => offerAmount -= 100)
                  : null,
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor: AppColors.primaryTint,
              ),
              child: const Text("- 100"),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  offerAmount += 100;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textPrimary,
              ),
              child: const Text("+ 100"),
            ),
          ],
        ),
        const SizedBox(height: 0),
        Row(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text("Auto-accept offer"),
                  const SizedBox(height: 8),
                  Switch(
                    value: autoAccept,
                    onChanged: (val) {
                      setState(() => autoAccept = val);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentRow() {
    return Row(
      children: const [
        Icon(Icons.credit_card, size: 20),
        SizedBox(width: 8),
        Text("Card"),
        Spacer(),
        Icon(Icons.arrow_drop_down),
      ],
    );
  }

  Widget _buildFindDriverButton() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => SearchDriverScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child:  Text("Find a driver",style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: _scheduleRide,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.all(14),
          ),
          child: const Icon(Icons.calendar_today, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}
