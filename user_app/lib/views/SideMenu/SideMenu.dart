import 'package:flutter/material.dart';
import 'dart:io';

import 'package:ravelgo_driver/views/User/user_summary.dart';


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
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: SizedBox(
                      width: 55,
                      height: 55,
                      child: _localImage('assets/fake_profile.png'), // preview image
                    ),
                  ),
                  SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const UserSummary(),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text("Thelma",
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        Text("Ibeh",
                            style: TextStyle(fontSize: 15, color: Colors.black54)),
                      ],
                    ),
                  ),
                ],
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
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.download, color: Colors.black87, size: 24),
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
                                      fontWeight: FontWeight.w600, fontSize: 15),
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
                              style: TextStyle(color: Colors.black54, fontSize: 13)),
                          SizedBox(height: 4),
                          Text('Update now',
                              style: TextStyle(
                                  color: Colors.blue,
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
              child: ListView(
                padding: EdgeInsets.only(top: 0),
                children: [
                  _menuItem(icon: Icons.history, label: "Trip history", onTap: () {}),
                  _menuItem(icon: Icons.grid_view_rounded, label: "Services", onTap: () {}),
                  _menuItem(
                      icon: Icons.calendar_month_outlined,
                      label: "Scheduled rides",
                      onTap: () {}),
                  _menuItem(
                      icon: Icons.card_giftcard_outlined,
                      label: "Refer a friend",
                      onTap: () {}),
                  _menuItem(
                      icon: Icons.person_outline,
                      label: "Account",
                      onTap: () {}),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // REUSABLE MENU ITEM WIDGET (ROUND CARD STYLE)
  Widget _menuItem(
      {required IconData icon,
        required String label,
        required VoidCallback onTap}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(
              children: [
                Icon(icon, size: 22, color: Colors.black87),
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

  // Local file preview
  Widget _localImage(String path) {
    final file = File(path);
    return file.existsSync()
        ? Image.file(file, fit: BoxFit.cover)
        : Container(color: Colors.grey[300]);
  }
}