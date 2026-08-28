import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views/AccountView/AppSettingsPage.dart';
import 'package:ravelgo_user_app/views/AccountView/CommunicationsPage.dart';
import 'package:ravelgo_user_app/views/AccountView/Subscription.dart';
import 'package:ravelgo_user_app/views/Driver_Portal/ravel_driver_portal_screen.dart';
import 'package:ravelgo_user_app/views/OtherViews/AboutView.dart';
import 'package:ravelgo_user_app/views/OtherViews/PrivacyScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class Accountview extends StatelessWidget {
  const Accountview({Key? key}) : super(key: key);

  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 18),

            /// Profile Section
            Center(
              child: Column(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 86,
                      height: 86,
                      child: Image.asset("assets/fake_profile.png",fit: BoxFit.fill,),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Thelma Ibeh',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.star, color: AppColors.success, size: 18),
                      SizedBox(width: 6),
                      Text(
                        '5.00 Rating',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),

            /// Section 1
            _section(
              children: [
                _menuRow(
                  icon: Icons.home_outlined,
                  label: 'Ravel driver portal',
                  onTap: (){
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => RavelDriverPortalScreen()),
                    );
                  }
                ),
                _divider(),
                _menuRow(
                  icon: Icons.directions_car_outlined,
                  label: 'Vehicle document',
                ),
                _divider(),
                _menuRow(
                  icon: Icons.subscriptions_outlined,
                  label: 'Subscription',
                  onTap: (){
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SubscriptionPage()),
                    );
                  }
                ),
              ],
            ),

            const SizedBox(height: 12),

            /// Section 2
            _section(
              children: [
                _menuRow(
                  icon: Icons.info_outline,
                  label: 'About',
                  onTap: (){
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => AboutView()),
                    );
                  }
                ),
                _divider(),
                _menuRow(
                  icon: Icons.shield_outlined,
                  label: 'Privacy',
                  onTap: (){
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => PrivacyScreen()),
                    );
                  }
                ),
                _divider(),
                _menuRow(
                  icon: Icons.map_outlined,
                  label: 'App Setting',
                  onTap: (){
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => AppSettingsPage()),
                    );
                  }
                ),
              ],
            ),

            const SizedBox(height: 12),

            /// Section 3
            Expanded(
              child: _section(
                children: [
                  _menuRow(
                    icon: Icons.campaign_outlined,
                    label: 'Communication',
                    onTap: (){
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => CommunicationsPage()),
                      );
                    }
                  ),
                  _divider(),
                  _menuRow(
                    icon: Icons.logout,
                    label: 'Log out',
                  ),
                  _divider(),
                  _menuRow(
                    icon: Icons.delete_outline,
                    label: 'Delete account',
                    labelColor: Colors.red,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Reusable Section Container
  Widget _section({required List<Widget> children}) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(children: children),
    );
  }

  /// Divider matching the UI
  Widget _divider() => Divider(height: 1, color: Colors.grey.shade300);

  /// Standard Row UI
  Widget _menuRow({
    required IconData icon,
    required String label,
    Color labelColor = Colors.black87,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Colors.black87),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: labelColor),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black45),
          ],
        ),
      ),
    );
  }

  /// Helper to load local preview image
  Widget _localImage(String path, {BoxFit fit = BoxFit.cover}) {
    final file = File(path);
    return file.existsSync()
        ? Image.file(file, fit: fit)
        : Container(color: Colors.grey.shade300, child: const Icon(Icons.person, size: 40));
  }
}