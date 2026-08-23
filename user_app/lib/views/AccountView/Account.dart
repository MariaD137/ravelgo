import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/auth_provider.dart';
import 'package:ravelgo_rider_app/services/api/rider_api.dart';
import 'package:ravelgo_rider_app/services/ride_session.dart';
import 'package:ravelgo_rider_app/views/AccountView/AppSettingsPage.dart';
import 'package:ravelgo_rider_app/views/AccountView/CommunicationsPage.dart';
import 'package:ravelgo_rider_app/views/AccountView/Subscription.dart';
import 'package:ravelgo_rider_app/views/Driver_Portal/ravel_driver_portal_screen.dart';
import 'package:ravelgo_rider_app/views/Login/login.dart';
import 'package:ravelgo_rider_app/views/OtherViews/AboutView.dart';
import 'package:ravelgo_rider_app/views/OtherViews/DeleteAccountScreen.dart';
import 'package:ravelgo_rider_app/views/OtherViews/PrivacyScreen.dart';

class Accountview extends StatefulWidget {
  Accountview({super.key, RiderApi? riderApi, AuthProvider? authProvider})
    : riderApi = riderApi ?? RiderApi(ApiClient()),
      authProvider = authProvider ?? createDefaultAuthProvider();

  final RiderApi riderApi;
  final AuthProvider authProvider;

  @override
  State<Accountview> createState() => _AccountviewState();
}

class _AccountviewState extends State<Accountview> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>?> _load() async {
    try {
      return await widget.riderApi.getMe();
    } on ApiException catch (err) {
      if (err.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> _logOut() async {
    await widget.authProvider.logout();
    RideSession.instance.clearTrip();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => Login(authProvider: widget.authProvider)),
      (route) => false,
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

            /// Profile Section — real name from GET /api/riders/me. There
            /// is no rider "rating" in this schema (Driver.rating exists;
            /// User/Rider does not), so the previous fixed "5.00 Rating"
            /// line is gone rather than replaced with another fake number.
            Center(
              child: Column(
                children: [
                  const ClipOval(
                    child: SizedBox(
                      width: 86,
                      height: 86,
                      child: CircleAvatar(backgroundColor: Colors.grey, child: Icon(Icons.person, size: 40, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<Map<String, dynamic>?>(
                    future: _future,
                    builder: (context, snapshot) {
                      final rider = snapshot.data;
                      final name = rider != null ? '${rider['firstName']} ${rider['lastName']}' : null;
                      return Text(
                        name ?? (snapshot.connectionState == ConnectionState.waiting ? 'Loading…' : 'Rider'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      );
                    },
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
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => RavelDriverPortalScreen()));
                  },
                ),
                _divider(),
                _menuRow(icon: Icons.subscriptions_outlined, label: 'Subscription', onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => SubscriptionPage()));
                }),
              ],
            ),

            const SizedBox(height: 12),

            /// Section 2
            _section(
              children: [
                _menuRow(icon: Icons.info_outline, label: 'About', onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => AboutView()));
                }),
                _divider(),
                _menuRow(icon: Icons.shield_outlined, label: 'Privacy', onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => PrivacyScreen()));
                }),
                _divider(),
                _menuRow(icon: Icons.map_outlined, label: 'App Setting', onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => AppSettingsPage()));
                }),
              ],
            ),

            const SizedBox(height: 12),

            /// Section 3
            Expanded(
              child: _section(
                children: [
                  _menuRow(icon: Icons.campaign_outlined, label: 'Communication', onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => CommunicationsPage()));
                  }),
                  _divider(),
                  _menuRow(icon: Icons.logout, label: 'Log out', onTap: _logOut),
                  _divider(),
                  _menuRow(
                    icon: Icons.delete_outline,
                    label: 'Delete account',
                    labelColor: Colors.red,
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const DeleteAccountScreen()));
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

  Widget _section({required List<Widget> children}) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(children: children),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.grey.shade300);

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
              child: Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: labelColor)),
            ),
            const Icon(Icons.chevron_right, color: Colors.black45),
          ],
        ),
      ),
    );
  }
}
