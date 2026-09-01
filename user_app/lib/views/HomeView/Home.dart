import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user_app/components/LocationService.dart';
import 'package:ravelgo_user_app/components/ride_controller.dart';
import 'package:ravelgo_user_app/components/SafeGoogleMap.dart';
import 'package:ravelgo_user_app/views/AppDrawer/AppDrawer.dart';
import 'package:ravelgo_user_app/views/HomeView/ride_view_popup.dart';
import 'package:ravelgo_user_app/views/User/invite_a_friend.dart';
import 'package:ravelgo_user_app/views/TexiModule/SelectRide.dart';
import 'package:ravelgo_user_app/views/Services/CarRentalScreen.dart';
import 'package:ravelgo_user_app/views/Services/IdelivaOnboardingScreen.dart';
import 'package:ravelgo_user_app/views/ServiceView/ServicesView.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/OtherViews/NotificationsScreen.dart';
import 'package:ravelgo_user_app/views/OtherViews/SafetyScreen.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Mock value, replace with live data. Kept in sync with the rating shown
  // on the Account screen for the same rider.
  final String _rating = "5.00";
  late GoogleMapController _controller;

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
  }
  Future<void> _loadCurrentLocation() async {
    final position = await LocationService.getCurrentLocation();
    if (position != null) {
      _controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 16.0,
          ),
        ),
      );

      // Optionally, animate camera here if using GoogleMapController
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
      backgroundColor: AppColors.background,
      body: SafeArea(

        child:ValueListenableBuilder<bool>(
            valueListenable: RideController.isRideActive,
            builder: (context, isRideActive, _) {
              return Stack(
                children: [
                  // Map / image background
                  SafeGoogleMap(
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

                  // Top-right notification bell
                  Positioned(
                    top: 12,
                    right: 64,
                    child: _circleIconButton(
                        icon: Icons.notifications_none,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                          );
                        }),
                  ),

                  // Top-right shield button
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _circleIconButton(
                        icon: Icons.shield_outlined,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SafetyScreen()),
                          );
                        }),
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
                        return  RideViewPopup(onClose: () {
                            RideController.stopRide();
                          },
                        );
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
      color: AppColors.surface.withOpacity(0.95),
      shape: CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: CircleBorder(),
        child: Padding(
          padding: EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  /// "Where to?" entry point into the ride-booking flow
  Widget _buildDestinationSearch() {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SelectRide()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            const Text(
              "Where to?",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  /// Reusable card container with light shadow
  Widget _cardContainer({required Widget child, BorderRadius? borderRadius}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: borderRadius ?? BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: AppColors.border, blurRadius: 6, offset: Offset(0, 2)),
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
              Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
            ],
          ),
          Spacer(),
          Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
        ],
      ),
    );
  }

  void _comingSoon(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name is coming soon to RavelGo.')),
    );
  }

  /// Multi-service launcher: the home is a hub, not just a ride screen. Ride,
  /// delivery, and rentals route into flows that already exist; Eats/Hotels are
  /// signposted as coming soon so the surface can grow as RavelGo expands.
  Widget _buildServicesLauncher() {
    final services = <(String, IconData, VoidCallback)>[
      ('Ride', Icons.local_taxi_outlined,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SelectRide()))),
      ('Delivery', Icons.local_shipping_outlined,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => IdelivaOnboardingScreen()))),
      ('Rentals', Icons.car_rental_outlined,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CarRentalScreen()))),
      ('Services', Icons.grid_view_outlined,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServicesView()))),
      ('Eats', Icons.restaurant_outlined, () => _comingSoon('Eats')),
      ('Hotels', Icons.hotel_outlined, () => _comingSoon('Hotels')),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: _cardContainer(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 10),
                child: Text('What do you need?',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.15,
                children: [
                  for (final s in services)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: s.$3,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(s.$2, size: 26, color: AppColors.primaryDark),
                            const SizedBox(height: 6),
                            Text(s.$1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeSheet(ScrollController scrollController) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
      ),
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [

            /// HEADER (Where to?)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.surface,
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
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),

                  _buildDestinationSearch(),
                ],
              ),
            ),

            const SizedBox(height: 14),

            /// Multi-service launcher
            _buildServicesLauncher(),

            const SizedBox(height: 12),

            /// Invite Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _cardContainer(
                child: ListTile(
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: const Icon(Icons.card_giftcard_outlined),
                  title: Text(
                    "Earn ${Currency.symbol}20,000",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text("Invite friends to RavelGo"),
                  trailing:
                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
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
                    _statRow("Your Rating", _rating),
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