import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views/OtherViews/EditProfileInfo.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class PersonalInfo extends StatelessWidget {
  const PersonalInfo({super.key});

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
    color: AppColors.surface, // 👈 Set background color here
    child: Column(
        children: [

          _ProfileSection(),
          const SizedBox(height: 30),
          const InfoTile(
            icon: Icons.person_outline,
            text: 'Thelma Ibeh',
          ),
          const InfoTile(
            icon: Icons.phone_outlined,
            text: '+2348130006677',
          ),
          const InfoTile(
            icon: Icons.email_outlined,
            text: 'user@gmail.com',
          ),
          const InfoTile(
            icon: Icons.lock_outline,
            text: 'John50c',
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
      width: double.infinity,// 👈 Set background color here
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

  const InfoTile({
    super.key,
    required this.icon,
    required this.text,
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
          trailing: const Icon(Icons.edit_outlined, color: AppColors.textSecondary),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => EditPersonalInfo()),
            );
          },
        ),
      ),
    );
  }
}