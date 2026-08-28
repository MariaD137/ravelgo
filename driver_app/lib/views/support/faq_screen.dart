import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class FAQScreen extends StatelessWidget {
  const FAQScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final faqs = [
      ("How do I go online?", "Toggle the online switch on your Home screen once your documents are approved."),
      ("When am I charged a cancellation fee?", "If you cancel a trip after arriving at the pickup location too many times, a cancellation charge applies."),
      ("How does fare negotiation work?", "You can propose a counter-fare when accepting a ride request; the rider can accept or decline it."),
      ("How do I renew my vehicle license?", "Use the Car Paddy feature in your Account menu to submit a renewal request."),
      ("How do subscriptions work?", "RavelGo offers weekly, monthly and quarterly subscription plans that lower your per-trip commission."),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text("FAQ")),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: faqs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final f = faqs[i];
          return Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Container(
              decoration: AppComponents.cardDecoration(),
              child: ExpansionTile(
                title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(alignment: Alignment.centerLeft, child: Text(f.$2, style: const TextStyle(color: AppColors.textSecondary))),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
