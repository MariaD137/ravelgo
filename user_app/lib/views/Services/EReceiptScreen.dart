import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class EReceiptScreen extends StatelessWidget {
  const EReceiptScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('E - Receipt'),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: const BackButton(color: AppColors.textPrimary),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: AppColors.surface,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Barcode
          Image.asset(
            'assets/barcode.png',
            height: 100,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 24),

          // Top summary block
          _infoTile('Plan Details', 'Daily'),
          _infoTile('Purchase Date', 'April 24,2025 | 10:00 AM'),
          _infoTile('Expiry Date', 'April 24,2025 | 10:00 AM'),
          _infoTile('Amount', 'NGN5,000'),
          _infoTile('Tax & Fees', 'NGN700'),
          _infoTile('Total', 'NGN5,700'),

          const SizedBox(height: 24),

          // User and payment info
          _infoRow('Name', 'John Harry'),
          _infoRow('Phone Number', '07037530000'),
          _infoRow('Payment Mode', 'Debit card'),
          _infoRow('Transaction ID', '#RE2564HG23'),
        ],
      ),

      // Bottom Download Button
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () {
              // Download PDF or share receipt
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Download E-receipt',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoTile(String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _infoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }
}