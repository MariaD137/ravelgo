import 'package:flutter/material.dart';
import 'package:ravelgo_user/views/AccountView/account.dart';
import 'package:ravelgo_user/views/HomeView/home.dart';
import 'package:ravelgo_user/views/RideView/rides_view.dart';
import 'package:ravelgo_user/views/ServiceView/services_view.dart';


class BottomNavigationView extends StatefulWidget {
  static final GlobalKey<MainBottomNavigationState> globalKey =
  GlobalKey<MainBottomNavigationState>();

  BottomNavigationView({Key? key}) : super(key: globalKey);

  @override
  MainBottomNavigationState createState() => MainBottomNavigationState();
}

class MainBottomNavigationState extends State<BottomNavigationView> {
  int _selectedIndex = 0;

  void changeTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }
  void _onTabTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    4,
        (index) => GlobalKey<NavigatorState>(),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildTabNavigator(0, HomePage()),
          _buildTabNavigator(1,  ServicesView()),
          _buildTabNavigator(2,  RidesView()),
          _buildTabNavigator(3,  Accountview()),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 15),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              topRight: Radius.circular(22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                spreadRadius: 0.5,
                blurRadius: 5,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            child: BottomNavigationBar(
              backgroundColor: const Color(0xFFFFFFFF),
              currentIndex: _selectedIndex,
              onTap: _onTabTapped,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: const Color(0xFFFFD700),
              unselectedItemColor: const Color(0xFFABABAB),
              showSelectedLabels: true,
              showUnselectedLabels: true,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.build), label: 'Service'),
                BottomNavigationBarItem(icon: Icon(Icons.directions_car), label: 'Rides'),
                BottomNavigationBarItem(icon: Icon(Icons.account_circle), label: 'Account'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabNavigator(int index, Widget child) {
    return Offstage(
      offstage: _selectedIndex != index,
      child: Navigator(
        key: _navigatorKeys[index],
        onGenerateRoute: (settings) {
          return MaterialPageRoute(builder: (_) => child);
        },
      ),
    );
  }
}