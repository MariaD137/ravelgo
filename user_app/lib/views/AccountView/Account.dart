import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/Model/app_state.dart';
import 'package:ravelgo_user_app/views/AccountView/AppSettingsPage.dart';
import 'package:ravelgo_user_app/views/AccountView/CommunicationsPage.dart';
import 'package:ravelgo_user_app/views/Login/login.dart';
import 'package:ravelgo_user_app/views/OtherViews/AboutView.dart';
import 'package:ravelgo_user_app/views/OtherViews/AddressSearch.dart';
import 'package:ravelgo_user_app/views/OtherViews/DeleteAccountScreen.dart';
import 'package:ravelgo_user_app/views/OtherViews/LoginSecurityScreen.dart';
import 'package:ravelgo_user_app/views/OtherViews/PaymentView.dart';
import 'package:ravelgo_user_app/views/OtherViews/PersonalInfo.dart';
import 'package:ravelgo_user_app/views/OtherViews/PrivacyScreen.dart';
import 'package:ravelgo_user_app/views/OtherViews/SupportView.dart';
import 'package:ravelgo_user_app/views/OtherViews/WorkProfileView.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class Accountview extends StatefulWidget {
  const Accountview({Key? key}) : super(key: key);

  @override
  State<Accountview> createState() => _AccountviewState();
}

class _AccountviewState extends State<Accountview> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
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
                  icon: Icons.person_outline,
                  label: 'Personal Info',
                  onTap: (){
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PersonalInfo()),
                    );
                  }
                ),
                _divider(),
                _menuRow(
                  icon: Icons.payment_outlined,
                  label: 'Payment methods',
                  onTap: (){
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => PaymentView()),
                    );
                  }
                ),
                _divider(),
                _menuRow(
                  icon: Icons.home_outlined,
                  label: 'Home address',
                  subtitle: RiderAppState.instance.savedAddresses['Home'],
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AddressSearch(addressType: "Home")),
                    );
                    if (mounted) setState(() {});
                  }
                ),
                _divider(),
                _menuRow(
                  icon: Icons.work_outline,
                  label: 'Work address',
                  subtitle: RiderAppState.instance.savedAddresses['Work'],
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AddressSearch(addressType: "Work")),
                    );
                    if (mounted) setState(() {});
                  }
                ),
                _divider(),
                _menuRow(
                  icon: Icons.business_center_outlined,
                  label: 'Work profile',
                  onTap: (){
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const WorkProfileView()),
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
                _divider(),
                _menuRow(
                  icon: Icons.lock_outline,
                  label: 'Login & Security',
                  onTap: (){
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LoginSecurityScreen()),
                    );
                  }
                ),
                _divider(),
                _menuRow(
                  icon: Icons.support_agent_outlined,
                  label: 'Contact support',
                  onTap: (){
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SupportView()),
                    );
                  }
                ),
              ],
            ),

            const SizedBox(height: 12),

            /// Section 3
            _section(
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
                    onTap: (){
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => Login()),
                        (route) => false,
                      );
                    }
                  ),
                  _divider(),
                  _menuRow(
                    icon: Icons.delete_outline,
                    label: 'Delete account',
                    labelColor: Colors.red,
                    onTap: (){
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const DeleteAccountScreen()),
                      );
                    }
                  ),
                ],
            ),
            const SizedBox(height: 18),
          ],
          ),
        ),
      ),
    );
  }

  /// Reusable Section Container
  Widget _section({required List<Widget> children}) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(children: children),
    );
  }

  /// Divider matching the UI
  Widget _divider() => Divider(height: 1, color: AppColors.border);

  /// Standard Row UI
  Widget _menuRow({
    required IconData icon,
    required String label,
    String? subtitle,
    Color labelColor = AppColors.textPrimary,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.textPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: labelColor),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
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
        : Container(color: AppColors.border, child: const Icon(Icons.person, size: 40));
  }
}