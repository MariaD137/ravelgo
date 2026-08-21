import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/ride_request.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/trip_service.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';

class TripCompleteScreen extends StatefulWidget {
  final RideRequest request;
  final String? tripId;
  const TripCompleteScreen({super.key, required this.request, this.tripId});

  @override
  State<TripCompleteScreen> createState() => _TripCompleteScreenState();
}

class _TripCompleteScreenState extends State<TripCompleteScreen> {
  int _rating = 0;
  bool _isSubmitting = false;

  Future<void> _submitAndFinish() async {
    setState(() => _isSubmitting = true);

    if (_rating > 0 && widget.tripId != null) {
      try {
        await ApiClient().post('/trips/${widget.tripId}/rating', body: {
          'rating': _rating,
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit rating, but your trip is complete.')),
        );
      }
    }

    if (widget.tripId != null) {
      try {
        await TripService().chargeTrip(widget.tripId!, method: 'CASH');
      } catch (e) {
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to charge rider: ${e.toString()}')),
        );
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DriverShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final platformFee = r.estimatedFare * 0.15;
    final earnings = r.estimatedFare - platformFee;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 56),
              const SizedBox(height: 12),
              const Text("Trip completed", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: AppComponents.cardDecoration(),
                child: Column(
                  children: [
                    _fareRow("Trip fare", "N${r.estimatedFare.toStringAsFixed(0)}"),
                    _fareRow("RavelGo service fee", "- N${platformFee.toStringAsFixed(0)}"),
                    AppComponents.divider(),
                    _fareRow("You earned", "N${earnings.toStringAsFixed(0)}", bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Text("Rate your rider", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text("Your rating is anonymous and helps keep RavelGo safe", style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 12),
              Row(
                children: List.generate(5, (i) {
                  final filled = i < _rating;
                  return IconButton(
                    onPressed: () => setState(() => _rating = i + 1),
                    icon: Icon(filled ? Icons.star : Icons.star_border, color: AppColors.primaryDark, size: 32),
                  );
                }),
              ),
              const Spacer(),
              _isSubmitting
                  ? const Center(child: CircularProgressIndicator())
                  : AppComponents.primaryButton(
                      text: "Done",
                      onPressed: _submitAndFinish,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fareRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
        ],
      ),
    );
  }
}
