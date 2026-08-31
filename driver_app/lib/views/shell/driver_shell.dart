import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
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
  bool _togglingOnline = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    // Make sure a driver row exists, then load the real record.
    try {
      await DriverApi.provisionMe();
    } catch (_) {
      // Non-fatal: e.g. not yet in the Driver group. getMe below will surface it.
    }
    try {
      final record = await DriverApi.getMe();
      if (!mounted) return;
      setState(() => _profile = DriverProfile.fromRecord(record));
    } catch (_) {
      // Leave the default profile; the home screen still renders.
    }
  }

  Future<void> _setOnline(bool value) async {
    if (_togglingOnline) return;
    setState(() => _togglingOnline = true);
    try {
      final record = await DriverApi.setOnline(value);
      if (!mounted) return;
      setState(() => _profile = _profile.copyWith(isOnline: record.isOnline, status: record.status));
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException && e.statusCode == 409
          ? 'Your account isn\'t approved to go online yet.'
          : (e is ApiException && e.statusCode == 403
              ? 'Your account isn\'t set up as a driver yet.'
              : e.toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _togglingOnline = false);
    }
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
        unselectedItemColor: AppColors.textMuted,
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
