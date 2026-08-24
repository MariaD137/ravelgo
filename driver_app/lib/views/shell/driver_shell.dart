import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/services/auth_session.dart';
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

  // Real driver sign-in (Cognito) doesn't exist in this app yet — see
  // AuthTokenProvider's doc comment. Until it does, presence/summary calls
  // will fail with "You need to sign in again." rather than silently using
  // a fake identity.
  late final DriverApi _driverApi = DriverApi(
    baseUrl: dotenv.env['API_BASE_URL'] ?? '',
    authTokenProvider: const NoAuthTokenProvider(),
  );

  // The backend is the source of truth for presence — this only flips
  // _profile.isOnline after the API confirms the change. A rejected
  // toggle (e.g. pending review / suspended) surfaces the backend's own
  // reason instead of silently changing the switch.
  Future<void> _setOnline(bool value) async {
    try {
      final confirmed = await _driverApi.setOnline(value);
      if (!mounted) return;
      setState(() => _profile = _profile.copyWith(isOnline: confirmed));
    } on DriverApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DriverHomeScreen(profile: _profile, onOnlineToggle: _setOnline, api: _driverApi),
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
