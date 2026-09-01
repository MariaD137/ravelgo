import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/Model/ride_lifecycle.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/bottommenu/BottomNavigationView.dart';

/// Post-trip driver rating (mirrors driver_app's rate-your-rider step).
/// LOCAL STATE ONLY: the rating is captured and acknowledged locally;
/// `_submit` is the integration point for the ratings backend.
class RateDriverScreen extends StatefulWidget {
  final RideOffer offer;
  const RateDriverScreen({super.key, required this.offer});

  @override
  State<RateDriverScreen> createState() => _RateDriverScreenState();
}

class _RateDriverScreenState extends State<RateDriverScreen> {
  int _rating = 0;
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    // Integration point: send {driver, rating, comment} to the ratings API.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => BottomNavigationView()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.check_circle, color: AppColors.success, size: 56),
              const SizedBox(height: 12),
              const Text('Trip completed', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('You rode with ${o.driverName} · ${o.fare}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 28),
              const Text('Rate your driver', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Your rating is anonymous and helps keep RavelGo safe',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final filled = i < _rating;
                  return IconButton(
                    onPressed: () => setState(() => _rating = i + 1),
                    icon: Icon(
                      filled ? Icons.star : Icons.star_border,
                      size: 34,
                      color: filled ? AppColors.warning : AppColors.textMuted,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _commentController,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Add a comment (optional)'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _rating > 0 ? _submit : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Submit rating'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _submit, child: const Text('Skip')),
            ],
          ),
        ),
      ),
    );
  }
}
