import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class CarPaddyScreen extends StatefulWidget {
  const CarPaddyScreen({super.key});

  @override
  State<CarPaddyScreen> createState() => _CarPaddyScreenState();
}

class _CarPaddyScreenState extends State<CarPaddyScreen> {
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Car Paddy")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Image.asset('assets/ic_rent_car.png', width: 36, height: 36),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Car Paddy lets you renew your vehicle license right from the app — no queues at the licensing office.",
                      style: TextStyle(fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppComponents.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Current license", style: TextStyle(fontWeight: FontWeight.w700)),
                      AppComponents.badge("Expiring soon", color: Colors.orange),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text("Vehicle registration (Car Papers) expires Aug 2, 2026", style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text("Start a renewal request", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            AppComponents.uploadBox("Upload current vehicle license"),
            const SizedBox(height: 10),
            AppComponents.uploadBox("Upload proof of roadworthiness"),
            const SizedBox(height: 10),
            const TextField(decoration: InputDecoration(labelText: "Vehicle plate number", border: OutlineInputBorder())),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text("Renewal service fee"),
                Text("₦7,500", style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 20),
            if (_submitted)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.success),
                    SizedBox(width: 10),
                    Expanded(child: Text("Renewal request submitted. We'll notify you once it's processed (1-3 business days).")),
                  ],
                ),
              )
            else
              AppComponents.primaryButton(text: "Submit renewal request", onPressed: () => setState(() => _submitted = true)),
          ],
        ),
      ),
    );
  }
}
