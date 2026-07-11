import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/account/account_screen.dart';
import 'package:ravelgo_driver_app/views/earnings/earnings_screen.dart';
import 'package:ravelgo_driver_app/views/home/driver_home_screen.dart';
import 'package:ravelgo_driver_app/views/shell/side_menu_driver.dart';
import 'package:ravelgo_driver_app/views/trips/my_trips_screen.dart';

class DriverShell extends StatefulWidget {
  const DriverShell({super.key});

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _index = 0;
  DriverProfile _profile = const DriverProfile();

  void _setOnline(bool value) {
    setState(() => _profile = _profile.copyWith(isOnline: value));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DriverHomeScreen(profile: _profile, onOnlineToggle: _setOnline),
      const MyTripsScreen(embedded: true),
      const EarningsScreen(embedded: true),
      const AccountScreen(embedded: true),
    ];

    return Scaffold(
      drawer: SideMenuDriver(profile: _profile),
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
  }
}
