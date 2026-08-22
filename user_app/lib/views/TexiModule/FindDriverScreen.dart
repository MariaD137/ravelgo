import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_driver/views/TexiModule/SearchDriverScreen.dart';

class FindDriverScreen extends StatefulWidget {
  const FindDriverScreen({super.key});

  @override
  State<FindDriverScreen> createState() => _FindDriverScreenState();
}

class _FindDriverScreenState extends State<FindDriverScreen> {
  // Captured via onMapCreated below for planned camera-follow behavior; not
  // read yet — kept for that, not dead code to delete.
  // ignore: unused_field
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
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

  Widget _buildTripInfoSheet(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTripDetail(),
          const SizedBox(height: 12),
          _buildOfferSection(),
          const SizedBox(height: 12),
          _buildCashRow(),
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
            Text("NGN 7,000", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Spacer(),
            ElevatedButton(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor: Colors.yellow[100],
              ),
              child: const Text("+ 100", style: TextStyle(color: Colors.black38)),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  offerAmount += 100;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.yellow[700],
                foregroundColor: Colors.black,
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

  Widget _buildCashRow() {
    return Row(
      children:  [
        Image.asset("assets/ic_cash_ride.png"),
        SizedBox(width: 8),
        Text("Cash"),
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
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child:  Text("Find a driver",style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.all(14),
          ),
          child: const Icon(Icons.calendar_today, color: Colors.black),
        ),
      ],
    );
  }
}
