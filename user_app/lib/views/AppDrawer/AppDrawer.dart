import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/components/initials_avatar.dart';
import 'package:ravelgo_user_app/services/auth_service.dart';
import 'package:ravelgo_user_app/services/rider_api.dart';
import 'package:ravelgo_user_app/views/HomeView/scheduled_rides_screen.dart';
import 'package:ravelgo_user_app/views/User/invite_a_friend.dart';
import 'package:ravelgo_user_app/views/bottommenu/BottomNavigationView.dart';

import '../User/user_summary.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';


/// The drawer header used to show a bundled stock portrait and the hardcoded
/// name "Thelma / Ibeh" for every rider. It now shows the signed-in rider's
/// own name and initials (GET /api/riders/me, falling back to the Cognito
/// session), and simply shows less when that hasn't loaded rather than
/// inventing someone.
class SideMenu extends StatefulWidget {
  const SideMenu({Key? key}) : super(key: key);

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  String? _name;
  String? _email;

  @override
  void initState() {
    super.initState();
    _email = AuthService.email;
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await RiderApi.getMe();
      if (!mounted || me == null) return;
      setState(() {
        _name = [me['firstName'], me['lastName']]
            .where((e) => e != null && '$e'.trim().isNotEmpty)
            .join(' ')
            .trim();
        _email = me['email']?.toString() ?? _email;
      });
    } catch (_) {
      // The drawer is navigation, not a report: it keeps the Cognito email
      // it already has rather than blocking the menu behind an error. Every
      // screen this drawer opens reports its own failures properly.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      elevation: 0,
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PROFILE SECTION
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child:
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const UserSummary(),
                    ),
                  );

                },
                child: Row(
                  children: [
                    InitialsAvatar(name: _name, size: 55),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (_name?.isNotEmpty ?? false) ? _name! : 'Your account',
                            style: TextStyle(
                                fontSize: 16, color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_email?.isNotEmpty ?? false)
                            Text(
                              _email!,
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.textMuted),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            ),

            SizedBox(height: 20),

            // MENU ITEMS
            Expanded(
              child:Container(
                decoration: BoxDecoration(color: Colors.transparent),
                child: ListView(
                  padding: EdgeInsets.only(top: 0),
                  children: [
                    _menuItem(assetsImg: "assets/trip_history.png", label: "Trip history", onTap: () {
                      BottomNavigationView.globalKey.currentState?.changeTab(2);
                      Navigator.pop(context);
                    }),
                    _menuItem(assetsImg: "assets/service.png", label: "Services", onTap: () {
                      BottomNavigationView.globalKey.currentState?.changeTab(1);
                      Navigator.pop(context);
                    }),
                    _menuItem(assetsImg: "assets/schedule_ride.png", label: "Scheduled rides", onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ScheduledRidesRequestsScreen(),
                        ),
                      );
                    }),
                    _menuItem(assetsImg: "assets/refer_a_friends.png", label: "Refer a friend", onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InviteFriendsView(),
                        ),
                      );
                    }),
                    _menuItem(assetsImg: "assets/ic_account.png", label: "Account", onTap: () {
                      BottomNavigationView.globalKey.currentState?.changeTab(3);
                      Navigator.pop(context);
                    }),
                  ],
                ),
              )
            ),


          ],
        ),
      ),
    );
  }

  // REUSABLE MENU ITEM WIDGET (ROUND CARD STYLE)
  Widget _menuItem(
      {required String assetsImg,
        required String label,
        required VoidCallback onTap}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(0),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(0),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(
              children: [
                Image.asset(assetsImg,height: 30,width: 30,),
                SizedBox(width: 16),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                ),
                Icon(Icons.chevron_right, size: 20, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

}