import 'package:flutter/material.dart';
import 'package:ravelgo/views/HomeView/scheduled_rides_screen.dart';
import 'package:ravelgo/views/User/invite_a_friend.dart';
import 'package:ravelgo/views/bottommenu/BottomNavigationView.dart';
import 'dart:io';

import '../User/user_summary.dart';


class SideMenu extends StatelessWidget {
  const SideMenu({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      elevation: 0,
      backgroundColor: Color(0xFFF6F6F6),
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: SizedBox(
                        width: 55,
                        height: 55,
                        child: Image.asset("assets/fake_profile.png"), // preview image
                      ),
                    ),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Thelma",
                            style: TextStyle(fontSize: 16, color: Color(0xFF3A3A3A))),
                        Text("Ibeh",
                            style: TextStyle(fontSize: 16, color: Color(0xFF3A3A3A))),
                      ],
                    ),
                  ],
                ),
              ),

            ),

            SizedBox(height: 10),

            // YELLOW UPDATE CARD
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(0xFFFFF6C8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Image.asset("assets/update_download.png",height: 30,width: 30,),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Your app needs an update',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 15,color: Color(0xFF3A3A3A)),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Icon(Icons.close, size: 18, color: Colors.black54),
                              )
                            ],
                          ),
                          SizedBox(height: 2),
                          Text('New features and improvements',
                              style: TextStyle(color: Color(0xFF757575), fontSize: 13)),
                          SizedBox(height: 4),
                          Text('Update now',
                              style: TextStyle(
                                  color: Color(0xFF665600),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
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
                    _menuItem(assetsImg: "assets/trip_history.png", label: "Trip history", onTap: () {}),
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
        color: Colors.white,
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
                Icon(Icons.chevron_right, size: 20, color: Colors.black45),
              ],
            ),
          ),
        ),
      ),
    );
  }

}