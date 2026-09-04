import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/services/auth_service.dart';
import 'package:ravelgo_user_app/services/rider_api.dart';
import 'package:ravelgo_user_app/views/OtherViews/EditProfileInfo.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class PersonalInfo extends StatefulWidget {
  const PersonalInfo({super.key});

  @override
  State<PersonalInfo> createState() => _PersonalInfoState();
}

class _PersonalInfoState extends State<PersonalInfo> {
  String? _firstName;
  String? _lastName;
  String? _phoneNumber;
  String? _email;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = await RiderApi.getMe();
      if (!mounted) return;
      setState(() {
        _firstName = me?['firstName']?.toString();
        _lastName = me?['lastName']?.toString();
        _phoneNumber = me?['phoneNumber']?.toString();
        _email = me?['email']?.toString() ?? AuthService.email;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _email = AuthService.email;
        _loading = false;
      });
    }
  }

  String get _name => [_firstName, _lastName]
      .where((e) => e != null && e.trim().isNotEmpty)
      .join(' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textPrimary),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Personal Info",
          style: TextStyle(color: AppColors.textPrimary),
        ),
      ),
      body: Container(
        color: AppColors.surface,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  const _ProfileSection(),
                  const SizedBox(height: 30),
                  InfoTile(
                    icon: Icons.person_outline,
                    text: _name.isNotEmpty ? _name : 'Add your name',
                    onSaved: _load,
                    firstName: _firstName,
                    lastName: _lastName,
                    phoneNumber: _phoneNumber,
                    email: _email,
                  ),
                  InfoTile(
                    icon: Icons.phone_outlined,
                    text: (_phoneNumber?.isNotEmpty ?? false) ? _phoneNumber! : 'Add your phone number',
                    onSaved: _load,
                    firstName: _firstName,
                    lastName: _lastName,
                    phoneNumber: _phoneNumber,
                    email: _email,
                  ),
                  InfoTile(
                    icon: Icons.email_outlined,
                    text: _email ?? '',
                    editable: false,
                  ),
                ],
              ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      height: 180,
      width: double.infinity,
      child: Column(
      children: [
        const SizedBox(height: 20),
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            const CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.textMuted,
              child: Icon(Icons.person, size: 40, color: AppColors.surface),
            ),
            Positioned(
              right: 0,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: AppColors.surface,
                child: Icon(Icons.edit, size: 14, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          "Upload a profile photo",
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const Text(
          "to help drivers identify you easily",
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
      ],
    ),);
  }
}

class InfoTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool editable;
  final VoidCallback? onSaved;
  final String? firstName;
  final String? lastName;
  final String? phoneNumber;
  final String? email;

  const InfoTile({
    super.key,
    required this.icon,
    required this.text,
    this.editable = true,
    this.onSaved,
    this.firstName,
    this.lastName,
    this.phoneNumber,
    this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.textMuted),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: Icon(icon, color: AppColors.textSecondary),
          title: Text(text),
          trailing: editable ? const Icon(Icons.edit_outlined, color: AppColors.textSecondary) : null,
          onTap: !editable
              ? null
              : () async {
                  final saved = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditPersonalInfo(
                        initialFirstName: firstName,
                        initialLastName: lastName,
                        initialPhoneNumber: phoneNumber,
                        email: email,
                      ),
                    ),
                  );
                  if (saved == true) onSaved?.call();
                },
        ),
      ),
    );
  }
}
