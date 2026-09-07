import 'package:flutter/material.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/dashboard/dashboard_screen.dart';
import 'package:ravelgo_admin/views/drivers/driver_list_screen.dart';
import 'package:ravelgo_admin/views/livemap/live_map_screen.dart';
import 'package:ravelgo_admin/views/notifications/notifications_screen.dart';
import 'package:ravelgo_admin/views/shell/side_menu_admin.dart';
import 'package:ravelgo_admin/views/support/support_tickets_screen.dart';
import 'package:ravelgo_admin/views/trips/trip_monitoring_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  static const _titles = ["Dashboard", "Live Monitoring", "Drivers", "Trips", "Support"];

  @override
  Widget build(BuildContext context) {
    final pages = const [
      DashboardScreen(embedded: true),
      LiveMapScreen(embedded: true),
      DriverListScreen(embedded: true),
      TripMonitoringScreen(embedded: true),
      SupportTicketsScreen(embedded: true),
    ];

    return Scaffold(
      drawer: const SideMenuAdmin(),
      appBar: AppBar(
        title: Text(_titles[_index]),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.notifications_none),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        selectedItemColor: AppColors.primaryDark,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: "Dashboard"),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: "Live Map"),
          BottomNavigationBarItem(icon: Icon(Icons.badge_outlined), label: "Drivers"),
          BottomNavigationBarItem(icon: Icon(Icons.alt_route_outlined), label: "Trips"),
          BottomNavigationBarItem(icon: Icon(Icons.support_agent_outlined), label: "Support"),
        ],
      ),
    );
  }
}
