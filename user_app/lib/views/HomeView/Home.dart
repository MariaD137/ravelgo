import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_rider_app/components/LocationService.dart';
import 'package:ravelgo_rider_app/services/ride_session.dart';
import 'package:ravelgo_rider_app/views/AppDrawer/AppDrawer.dart';
import 'package:ravelgo_rider_app/views/HomeView/ride_view_popup.dart';
import 'package:ravelgo_rider_app/views/TexiModule/FindRoute.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
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
    try {
      final position = await LocationService.getCurrentLocation();
      if (!mounted) return;
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
    } on LocationException catch (err) {
      // Distinguishable by err.reason if a caller ever needs to branch on
      // it (e.g. prompting to open settings for permissionDeniedForever) —
      // this screen just logs which one occurred instead of a single
      // generic "failed" message.
      debugPrint('Home: could not load current location (${err.reason}): ${err.message}');
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

  Widget _buildHomeSheet(ScrollController scrollController) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF2F2F4),
        borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
      ),
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            /// Drag Handle
            Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
            ),

            /// "Where to?" — the real entry point into requesting a ride
            /// (FindRouteScreen -> SelectRide -> the actual backend-wired
            /// matching flow), not a placeholder.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _cardContainer(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: const Icon(Icons.search),
                  title: const Text(
                    "Where to?",
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const FindRouteScreen()));
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}