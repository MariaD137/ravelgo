import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class AboutView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  BackButton(color: AppColors.textPrimary),
                  Spacer(),
                  Text(
                    'About Ravel Go',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.normal, color: AppColors.textPrimary),
                  ),
                  Spacer(),
                  SizedBox(width: 64)
                ],
              ),
            ),
          ),
        ),
      ),
      backgroundColor: AppColors.surface,
      body: ListView(
        children: [
          ListTile(
            title: Text('Where does Ravel Go operate',style: TextStyle(fontSize: 16, fontWeight: FontWeight.normal, color: AppColors.textPrimary),),
            trailing: Icon(Icons.arrow_forward_ios),
            onTap: () {
              // Action for tapping the first item
              // Navigate to the corresponding screen or show details
            },
          ),
          ListTile(
            title: Text('Where is Ravel Go office located',style: TextStyle(fontSize: 16, fontWeight: FontWeight.normal, color: AppColors.textPrimary),),
            trailing: Icon(Icons.arrow_forward_ios),
            onTap: () {
              // Action for tapping the second item
              // Navigate to the corresponding screen or show details
            },
          ),
        ],
      ),
    );
  }
}