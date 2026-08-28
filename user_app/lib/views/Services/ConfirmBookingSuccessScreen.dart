import 'package:flutter/material.dart';
import '../bottommenu/BottomNavigationView.dart';
import 'EReceiptScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class ConfirmBookingSuccessScreen extends StatelessWidget {
  const ConfirmBookingSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              // Back icon manually styled like the image
              Align(
                alignment: Alignment.topLeft,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(24),
                  child: const CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.background,
                    child: Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              const Icon(Icons.check_circle, size: 100, color: Colors.green),
              const SizedBox(height: 24),
              const Text(
                'Congratulation!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'You have successfully subscribed yearly plan.\nYou can download your E-receipt Now',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const Spacer(),

              // Buttons
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (context)=> EReceiptScreen()));
                      },
                      child: const Text(
                        'View E-receipt',
                        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) =>  BottomNavigationView()), // replace with your actual HomeView widget
                              (route) => false, // remove all previous routes
                        );
                      },
                      child: const Text(
                        'Go to Rent a car',
                        style: TextStyle(color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}