import 'package:flutter/material.dart';
import 'package:ravelgo_user/services/api_client.dart';
import 'package:ravelgo_user/services/auth_service.dart';
import 'package:ravelgo_user/views/AccountView/AppSettingsPage.dart';
import 'package:ravelgo_user/views/AccountView/CommunicationsPage.dart';
import 'package:ravelgo_user/views/AccountView/Subscription.dart';
import 'package:ravelgo_user/views/Driver_Portal/ravel_driver_portal_screen.dart';
import 'package:ravelgo_user/views/Login/login.dart';
import 'package:ravelgo_user/views/OtherViews/AboutView.dart';
import 'package:ravelgo_user/views/OtherViews/DeleteAccountScreen.dart';
import 'package:ravelgo_user/views/OtherViews/PrivacyScreen.dart';

class Accountview extends StatefulWidget {
  const Accountview({Key? key}) : super(key: key);

  @override
  State<Accountview> createState() => _AccountviewState();
}

class _AccountviewState extends State<Accountview> {
  String _userName = '';
  String _rating = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await ApiClient().get('/riders/me');
      if (!mounted) return;
      setState(() {
        final firstName = data['firstName'] ?? '';
        final lastName = data['lastName'] ?? '';
        _userName = '$firstName $lastName'.trim();
        final ratingValue = data['rating'];
        _rating = ratingValue != null ? '${double.tryParse(ratingValue.toString())?.toStringAsFixed(2) ?? ratingValue} Rating' : '';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await AuthService().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => Login()),
      (Route<dynamic> route) => false,
    );
  }

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
                  Text(
                    _loading ? '...' : (_userName.isNotEmpty ? _userName : 'User'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  if (_rating.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: Color(0xFF00B14B), size: 18),
                        const SizedBox(width: 6),
                        Text(
                          _rating,
                          style: const TextStyle(fontWeight: FontWeight.w600),
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
                    onTap: () => _logout(),
                  ),
                  _divider(),
                  _menuRow(
                    icon: Icons.delete_outline,
                    label: 'Delete account',
                    labelColor: Colors.red,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const DeleteAccountScreen()),
                      );
                    },
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

}