import 'package:flutter/material.dart';
import 'PlanReviewSummaryScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class ChoosePlanScreen extends StatelessWidget {
  const ChoosePlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> plans = [
      {
        'price': 'NGN5,000',
        'duration': 'Daily',
        'features': [
          'Post your car on a single-day basis',
          'Limited to one car daily',
          'Ad-free experience',
        ]
      },
      {
        'price': 'NGN9,000',
        'duration': 'Weekly',
        'features': [
          'keep your vehicle listed for 7 days',
          'Enable to post multiple cars',
          'Access to live chat support',
          'Ad-free experience',
        ]
      },
      {
        'price': 'NGN13,000',
        'duration': 'Monthly',
        'features': [
          'keep your vehicle listed for 1 month',
          'Enable to post multiple cars',
          'Access to live chat support',
          'Ad-free experience',
        ]
      },
      {
        'price': 'NGN18,000',
        'duration': '6 Months',
        'features': [
          'keep your vehicle listed for 1 month',
          'Enable to post multiple cars',
          'Access to live chat support',
          'Ad-free experience',
        ]
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose your plan'),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: BackButton(color: AppColors.textPrimary),
        titleTextStyle: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
      ),
      backgroundColor: AppColors.surface,
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: plans.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final plan = plans[index];
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    text: '${plan['price']} ',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    children: [
                      TextSpan(
                        text: '/${plan['duration']}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ...plan['features'].map<Widget>((feature) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, size: 20, color: AppColors.textPrimary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            feature,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => PlanReviewSummaryScreen()),
                      );
                    },
                    child: const Text('Select Plan', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}