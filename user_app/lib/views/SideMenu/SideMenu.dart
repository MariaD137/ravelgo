import 'package:flutter/material.dart';

import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/rider_api.dart';
import 'package:ravelgo_rider_app/views/AccountView/Account.dart';
import 'package:ravelgo_rider_app/views/HomeView/scheduled_rides_screen.dart';
import 'package:ravelgo_rider_app/views/RideView/RidesView.dart';
import 'package:ravelgo_rider_app/views/ServiceView/ServicesView.dart';
import 'package:ravelgo_rider_app/views/User/invite_a_friend.dart';
import 'package:ravelgo_rider_app/views/User/user_summary.dart';

class SideMenu extends StatefulWidget {
  SideMenu({super.key, RiderApi? riderApi}) : riderApi = riderApi ?? RiderApi(ApiClient());

  final RiderApi riderApi;

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>?> _load() async {
    try {
      return await widget.riderApi.getMe();
    } on ApiException catch (err) {
      if (err.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      elevation: 0,
      backgroundColor: const Color(0xFFF6F6F6),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PROFILE SECTION — real rider name from GET /api/riders/me.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: const SizedBox(
                      width: 55,
                      height: 55,
                      child: CircleAvatar(backgroundColor: Colors.grey, child: Icon(Icons.person, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => UserSummary()));
                    },
                    child: FutureBuilder<Map<String, dynamic>?>(
                      future: _future,
                      builder: (context, snapshot) {
                        final rider = snapshot.data;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rider != null ? rider['firstName'] as String : (snapshot.connectionState == ConnectionState.waiting ? 'Loading…' : 'Rider'),
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                            ),
                            if (rider != null)
                              Text(rider['lastName'] as String, style: const TextStyle(fontSize: 15, color: Colors.black54)),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // YELLOW UPDATE CARD
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFFFF6C8), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.download, color: Colors.black87, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text('Your app needs an update', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: const Icon(Icons.close, size: 18, color: Colors.black54),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text('New features and improvements', style: TextStyle(color: Colors.black54, fontSize: 13)),
                          const SizedBox(height: 4),
                          const Text('Update now', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600, fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // MENU ITEMS — each now navigates to the real screen it names.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 0),
                children: [
                  _menuItem(
                    icon: Icons.history,
                    label: "Trip history",
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => RidesView())),
                  ),
                  _menuItem(
                    icon: Icons.grid_view_rounded,
                    label: "Services",
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ServicesView())),
                  ),
                  _menuItem(
                    icon: Icons.calendar_month_outlined,
                    label: "Scheduled rides",
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ScheduledRidesRequestsScreen()),
                    ),
                  ),
                  _menuItem(
                    icon: Icons.card_giftcard_outlined,
                    label: "Refer a friend",
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const InviteFriendsView())),
                  ),
                  _menuItem(
                    icon: Icons.person_outline,
                    label: "Account",
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => Accountview())),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem({required IconData icon, required String label, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(
              children: [
                Icon(icon, size: 22, color: Colors.black87),
                const SizedBox(width: 16),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
                const Icon(Icons.chevron_right, size: 20, color: Colors.black45),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
