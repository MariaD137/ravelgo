import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/components/ride_controller.dart';
import 'package:ravelgo_user_app/views/AppDrawer/AppDrawer.dart';
import 'package:ravelgo_user_app/views/HomeView/ride_view_popup.dart';
import 'package:ravelgo_user_app/views/User/invite_a_friend.dart';
import 'package:ravelgo_user_app/views/TexiModule/SelectRide.dart';
import 'package:ravelgo_user_app/views/Services/CarRentalScreen.dart';
import 'package:ravelgo_user_app/views/Delivery/SendPackageScreen.dart';
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
                  // Plain background behind the top icons and the home sheet
                  // below — purely decorative, so nothing here depends on it.
                  Positioned.fill(child: Container(color: AppColors.background)),


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
                      // With the decorative map gone, there's no background
                      // left worth revealing by dragging the sheet down — so
                      // it now opens filling almost the whole screen instead
                      // of leaving a large empty gap above it.
                      initialChildSize: 0.88,
                      minChildSize: 0.55,
                      maxChildSize: 0.95,
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

  /// Multi-service launcher: Ride, Car Rentals, and Delivery route into flows
  /// that already exist and have real photography, shown as Uber-style photo
  /// cards. Services is already reachable from the bottom nav bar, and
  /// Eats/Hotels have no photography yet, so none of the three get a tile
  /// here.
  void _showComingSoon(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Coming soon'),
        content: Text('$feature is coming soon.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _buildServicesLauncher() {
    // Each card image already has its own title, description, icon badge and
    // "go" arrow baked in by design, so these render as full self-contained
    // tiles with no separate label overlaid on top.
    final photoServices = <(String, String, VoidCallback)>[
      ('Ride', 'assets/card_ride.png',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SelectRide()))),
      ('Car Rentals', 'assets/card_car_rental.png',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CarRentalScreen()))),
      ('Delivery', 'assets/card_delivery.png',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SendPackageScreen()))),
      ('Short stay rentals', 'assets/card_short_stay.png', () => _showComingSoon(context, 'Short stay rentals')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16, bottom: 10),
          child: Text('What do you need?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: photoServices.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final s = photoServices[i];
              return Semantics(
                button: true,
                label: s.$1,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: s.$3,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(color: AppColors.border, blurRadius: 6, offset: const Offset(0, 2)),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(s.$2, width: 160, height: 160, fit: BoxFit.cover),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHomeSheet(ScrollController scrollController) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
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
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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

                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    // Source image is a wide crop (1080x691) showing the
                    // whole car with the RavelGo logo. Sheet width is now
                    // capped above, so this only trims a little off the
                    // sides instead of squashing the whole car vertically.
                    child: Image.asset(
                      'assets/hero_banner.jpg',
                      width: double.infinity,
                      height: 260,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),
                  const SizedBox(height: 12),

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