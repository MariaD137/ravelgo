import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_rider_app/views/TexiModule/CancelRideScreen.dart';
import 'package:ravelgo_rider_app/views/TexiModule/RequestDriverScreen.dart';

class SearchDriverScreen extends StatefulWidget {
  const SearchDriverScreen({super.key});

  @override
  State<SearchDriverScreen> createState() => _SearchDriverScreenState();
}

class _SearchDriverScreenState extends State<SearchDriverScreen> {
  // Captured via onMapCreated below for planned camera-follow behavior; not
  // read yet — kept for that, not dead code to delete.
  // ignore: unused_field
  GoogleMapController? _mapController;
  double offerAmount = 3500;
  double paymentAmount = 7000;
  bool autoAccept = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) => _mapController = controller,
            initialCameraPosition: const CameraPosition(
              target: LatLng(6.5244, 3.3792),
              zoom: 14,
            ),
            myLocationEnabled: true,
            zoomControlsEnabled: false,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildSearchBar(),
            ),
          ),

          DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.3,
            maxChildSize: 0.65,
            builder: (context, scrollController) {
              return
                Container(
                  decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 10),
              ],
              ),
              child:
              Column(
                children:[
                  _buildDriverViewingBanner(),
                  Expanded(
                    child: ListView(
                        controller: scrollController,
                        children: [
                            _buildBottomSheet(),
                        ]
                      ),
                    ),
                  _buildCancelButton(),
                  const SizedBox(height: 0),
                  ]
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
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
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

  Widget _buildDriverViewingBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 0),
      padding: const EdgeInsets.only(left: 8,right: 8,top: 8,bottom: 18),
      decoration: BoxDecoration(
        color: Colors.yellow[700],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(children: [
        Container(
          width: 40,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.grey[400],
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("5 drivers are viewing  your request", style: TextStyle(fontWeight: FontWeight.w500)),
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => RequestDriverScreen()),
                );
              },
              child:   Row(
                children: List.generate(4, (index) =>
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                      child: CircleAvatar(radius: 12, backgroundImage: AssetImage('assets/ic_avatar$index.png')),
                    ),
                ),
              ),
            ),
         ],
        ),
        ],
      ),
    );
  }

  Widget _buildBottomSheet() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 0)],
      ),
      child: Column(

        mainAxisSize: MainAxisSize.min,
        children: [

          Container(
            padding: const EdgeInsets.all(35),
            decoration: BoxDecoration(
              color: Colors.yellow[100],
              shape: BoxShape.circle,
            ),
            child: Column(
              children: [
                const Text("Finding drivers...", style: TextStyle(fontWeight: FontWeight.w500,fontSize: 14)),
                const SizedBox(height: 40),
                const Text("Your offer", style: TextStyle(fontWeight: FontWeight.w500,fontSize: 16,color: Colors.grey)),
                Text("NGN $offerAmount", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildTripInfo(),
          const SizedBox(height: 10),
          _buildCashRow(),
          const SizedBox(height: 10),
        ],
      ),
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
  Widget _buildTripInfo() {
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
        Text("Payment", style: TextStyle(fontWeight: FontWeight.w500)),
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

  Widget _buildCancelButton() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent, // To allow rounded corners
                builder: (context) {
                  return FractionallySizedBox(
                    heightFactor: 0.8, // 80% of screen height
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      child: const CancelRideScreen(),
                    ),
                  );
                },
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.yellow[700],
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text("Cancel request"),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.yellow[700],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.all(14),
          ),
          child: const Icon(Icons.calendar_today, color: Colors.black),
        ),
      ],
    );
  }
}
