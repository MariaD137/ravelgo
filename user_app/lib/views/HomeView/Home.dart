import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_rider_app/components/LocationService.dart';
import 'package:ravelgo_rider_app/services/ride_session.dart';
import 'package:ravelgo_rider_app/views/AppDrawer/AppDrawer.dart';
import 'package:ravelgo_rider_app/views/HomeView/ride_view_popup.dart';
import 'package:ravelgo_rider_app/views/User/invite_a_friend.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isOnline = false;

  // Mock values, replace with live data
  final String _rating = "80%";
  final String _acceptance = "20%";
  late GoogleMapController _controller;
  // Written by _loadCurrentLocation() to trigger the camera-follow rebuild
  // below; not read directly yet — kept for the planned "show my location"
  // marker, not dead code to delete.
  // ignore: unused_field
  Position? _currentPosition;

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
  }
  Future<void> _loadCurrentLocation() async {
    final position = await LocationService.getCurrentLocation();
    if (position != null) {
      setState(() {
        _currentPosition = position;
      });
      _controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 16.0,
          ),
        ),
      );

      // Optionally, animate camera here if using GoogleMapController
    } else {
      print("⚠️ Failed to get location.");
    }
  }
  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(20.5937, 78.9629), // Default center (India in this case)
    zoom: 5.0,
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 300), _loadCurrentLocation);

  }
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      key: _scaffoldKey,
      drawer: SideMenu(),
      backgroundColor: Color(0xFFF2F2F4),
      body: SafeArea(

        child:AnimatedBuilder(
            animation: RideSession.instance,
            builder: (context, _) {
              final isRideActive = RideSession.instance.hasActiveTrip;
              return Stack(
                children: [
                  // Map / image background
                  GoogleMap(
                    mapType: MapType.hybrid,
                    onMapCreated: _onMapCreated,
                    initialCameraPosition: _initialCameraPosition,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    compassEnabled: false,
                  ),


                  // Top-left menu button (circular)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _circleIconButton(icon: Icons.menu, onTap: () {
                      _scaffoldKey.currentState?.openDrawer();
                    }),
                  ),

                  // Top-right shield button
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _circleIconButton(
                        icon: Icons.shield_outlined, onTap: () {}),
                  ),


                  /// HOME SHEET
                  if (!isRideActive)
                    DraggableScrollableSheet(
                      initialChildSize: 0.35,
                      minChildSize: 0.2,
                      maxChildSize: 0.55,
                      builder: (context, scrollController) {
                        return _buildHomeSheet(scrollController);
                      },
                    ),

                  /// RIDE POPUP
                  if (isRideActive)
                    DraggableScrollableSheet(
                      initialChildSize: 0.35,
                      minChildSize: 0.2,
                      maxChildSize: 0.8,
                      builder: (context, scrollController) {
                        // RideSession already notifies this AnimatedBuilder
                        // when the trip is cleared — no separate stop-ride
                        // call needed here.
                        return RideViewPopup(onClose: () {});
                      },
                    ),

                ],
              );
            },
        ),
      ),
    );
  }

  /// Small circular icon button used near map top corners
  Widget _circleIconButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.white.withOpacity(0.95),
      shape: CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: CircleBorder(),
        child: Padding(
          padding: EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: Colors.black87),
        ),
      ),
    );
  }

  /// Mock toggle widget styled like the design
  Widget _buildToggle() {
    return GestureDetector(
      onTap: () => setState(() => _isOnline = !_isOnline),
      child: Container(
        width: 56,
        height: 30,
        padding: EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _isOnline ? Colors.green : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Align(
          alignment: _isOnline ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 2)],
            ),
          ),
        ),
      ),
    );
  }

  /// Reusable card container with light shadow
  Widget _cardContainer({required Widget child, BorderRadius? borderRadius}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius ?? BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }

  /// Statistic row with label and value aligned like design
  Widget _statRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 15)),
              SizedBox(height: 2),
              Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB08A00))),
            ],
          ),
          Spacer(),
          Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, thickness: 1, color: Colors.grey[300]);

  Widget _buildHomeSheet(ScrollController scrollController) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFB8BABE),
        borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
      ),
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [

            /// HEADER (Yellow Section)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: const BoxDecoration(
                color: Color(0xFFFFD500),
                borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
              ),
              child: Column(
                children: [

                  /// Drag Handle
                  Container(
                    width: 48,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),

                  /// Toggle + Safety Row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        _buildToggle(),
                        const SizedBox(width: 10),
                        const Text(
                          "Get Online",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            /// Invite Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _cardContainer(
                child: ListTile(
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: const Icon(Icons.card_giftcard_outlined),
                  title: const Text(
                    "Earn ₹20,000",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text("Invite friends to drive"),
                  trailing:
                  const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const InviteFriendsView(),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 12),

            /// Stats Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _cardContainer(
                child: Column(
                  children: [
                    _statRow("Driver Rating / Score", _rating),
                    _divider(),
                    _statRow("Daily Earnings", "₹0"),
                    _divider(),
                    _statRow("Acceptance Rate", _acceptance),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}