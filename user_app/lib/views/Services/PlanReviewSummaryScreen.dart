import 'package:flutter/material.dart';
import 'ConfirmBookingSuccessScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class PlanReviewSummaryScreen extends StatelessWidget {
  const PlanReviewSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review summary'),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: const BackButton(color: AppColors.textPrimary),
        titleTextStyle: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 18),
      ),
      backgroundColor: AppColors.surface,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Selected Plan Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              border: Border.all(color: AppColors.primary),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: const TextSpan(
                    text: 'NGN5,000 ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    children: [
                      TextSpan(
                        text: '/Daily',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const _FeatureItem(text: 'Post your car on a single-day basis'),
                const _FeatureItem(text: 'Limited to one car daily'),
                const _FeatureItem(text: 'Ad-free experience'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Select Plan', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Payment Summary
          const _SummaryRow(label: 'Amount', value: 'NGN5,000'),
          const _SummaryRow(label: 'Tax & Fees', value: 'NGN700'),
          const _SummaryRow(label: 'Total', value: 'NGN5,700'),

          const SizedBox(height: 24),

          // Payment Method
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('VISA', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('**** **** **** 5327', style: TextStyle(fontWeight: FontWeight.w500)),
                  Text('Expires 09/24', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
              TextButton(
                onPressed: () {
                  // Change card action
                },
                child: const Text('Change', style: TextStyle(color: Colors.brown, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface, // Background color
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withOpacity(0.1), // Soft shadow
              blurRadius: 10,
              offset: const Offset(0, -2), // Upward shadow
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {

              Navigator.of(context).push(MaterialPageRoute(builder: (context)=>ConfirmBookingSuccessScreen()));
              // ConfirmBookingSuccessScreen
            },
            child: const Text(
              'Confirm payment',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final String text;
  const _FeatureItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.textPrimary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}