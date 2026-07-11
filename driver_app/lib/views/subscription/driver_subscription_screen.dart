import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class _Plan {
  final String name;
  final String price;
  final List<String> perks;
  const _Plan(this.name, this.price, this.perks);
}

class DriverSubscriptionScreen extends StatefulWidget {
  const DriverSubscriptionScreen({super.key});

  @override
  State<DriverSubscriptionScreen> createState() => _DriverSubscriptionScreenState();
}

class _DriverSubscriptionScreenState extends State<DriverSubscriptionScreen> {
  int _selected = 1;

  static const _plans = [
    _Plan("Weekly", "₦3,500 / week", ["Lower per-trip commission", "Priority ride matching"]),
    _Plan("Monthly", "₦12,000 / month", ["Lowest commission rate", "Priority ride matching", "Free Car Paddy renewal reminders"]),
    _Plan("Quarterly", "₦32,000 / quarter", ["Lowest commission rate", "Priority ride matching", "Dedicated support line"]),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Subscription Plan")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "RavelGo runs on a subscription model for drivers. Choose a plan to keep driving with lower fees.",
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 20),
          ...List.generate(_plans.length, (i) {
            final p = _plans[i];
            final selected = _selected == i;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () => setState(() => _selected = i),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? AppColors.primaryDark : Colors.black26),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(p.price, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      ...p.perks.map((perk) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(children: [
                              const Icon(Icons.check, size: 14, color: AppColors.success),
                              const SizedBox(width: 6),
                              Expanded(child: Text(perk, style: const TextStyle(fontSize: 12.5))),
                            ]),
                          )),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          AppComponents.primaryButton(text: "Subscribe", onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}
