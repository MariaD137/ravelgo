import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/account/account_screen.dart';
import 'package:ravelgo_driver_app/views/earnings/earnings_screen.dart';
import 'package:ravelgo_driver_app/views/home/driver_home_screen.dart';
import 'package:ravelgo_driver_app/views/shell/side_menu_driver.dart';
import 'package:ravelgo_driver_app/views/trips/my_trips_screen.dart';

/// The real driver profile (GET /api/drivers/me, via
/// [DriverSession.loadProfile]) is loaded once here, before any tab is
/// shown — replacing the previous `DriverProfile _profile = const
/// DriverProfile()` local default that meant every driver saw a fixed
/// placeholder name/rating/trip-count regardless of who actually signed in.
class DriverShell extends StatefulWidget {
  const DriverShell({super.key});

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _index = 0;
  late Future<bool> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = DriverSession.instance.loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<bool>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Failed to load your profile: ${snapshot.error}', textAlign: TextAlign.center),
              ),
            );
          }
          if (snapshot.data != true) {
            // GET /api/drivers/me 404d — no backend Driver row for this
            // account yet. Shown honestly rather than falling back to a
            // fabricated profile.
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.person_off_outlined, size: 48, color: Colors.black38),
                    SizedBox(height: 16),
                    Text(
                      "Your driver profile isn't set up yet",
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                    Text(
                      "Complete driver onboarding to start receiving ride, courier, and rental requests.",
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListenableBuilder(
            listenable: DriverSession.instance,
            builder: (context, _) {
              final profile = DriverSession.instance.profile!;
              final pages = [const DriverHomeScreen(), const MyTripsScreen(embedded: true), const EarningsScreen(embedded: true), const AccountScreen(embedded: true)];
              return Scaffold(
                drawer: SideMenuDriver(profile: profile),
                body: pages[_index],
                bottomNavigationBar: BottomNavigationBar(
                  currentIndex: _index,
                  onTap: (i) => setState(() => _index = i),
                  selectedItemColor: AppColors.primaryDark,
                  unselectedItemColor: Colors.grey,
                  type: BottomNavigationBarType.fixed,
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: "Home"),
                    BottomNavigationBarItem(icon: Icon(Icons.list_alt_outlined), label: "Trips"),
                    BottomNavigationBarItem(icon: Icon(Icons.payments_outlined), label: "Earnings"),
                    BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: "Account"),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
