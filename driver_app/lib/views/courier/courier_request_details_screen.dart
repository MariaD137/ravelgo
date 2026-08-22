import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_operational_state.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/courier/active_delivery_screen.dart';

/// Step 2 of the real driver courier flow: shows one request's details and
/// lets the driver accept it (PATCH /api/courier-requests/:id/accept on the
/// real backend). A DRIVER_BUSY 409 — the driver already holds an active
/// Ride/Courier/Rental assignment — is a normal, expected outcome here, not
/// an error to hide: the backend is the authority (Part 18), so this screen
/// surfaces exactly what it said rather than assuming the accept would
/// succeed just because the UI let the driver tap the button.
class CourierRequestDetailsScreen extends StatefulWidget {
  const CourierRequestDetailsScreen({super.key, required this.request});

  final Map<String, dynamic> request;

  @override
  State<CourierRequestDetailsScreen> createState() => _CourierRequestDetailsScreenState();
}

class _CourierRequestDetailsScreenState extends State<CourierRequestDetailsScreen> {
  bool _accepting = false;

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      final accepted = await DriverSession.instance.courierApi.accept(widget.request['id'] as String);
      DriverSession.instance.markBusy(
        DriverOperationalState.onCourier,
        accepted['id'] as String,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ActiveDeliveryScreen(request: accepted)),
      );
    } on ApiException catch (err) {
      if (!mounted) return;
      if (err.code == 'DRIVER_BUSY') {
        DriverSession.instance.reconcile(
          busy: true,
          assignmentType: err.body?['activeAssignmentType'] as String?,
          assignmentId: err.body?['activeAssignmentId'] as String?,
        );
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Already on a job'),
            content: Text(err.message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
            ],
          ),
        );
        if (mounted) Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
        if (mounted) Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            AppComponents.header(context, 'Delivery request'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppComponents.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r['packageDescription'] as String? ?? 'Package',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                      ),
                      const SizedBox(height: 16),
                      _row('Pickup', r['pickupAddress'] as String? ?? ''),
                      _row('Dropoff', r['dropoffAddress'] as String? ?? ''),
                      _row('Recipient', r['recipientName'] as String? ?? ''),
                      _row('Recipient phone', r['recipientPhone'] as String? ?? ''),
                      _row('Fare', '₦${r['estimatedFare']}'),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppComponents.primaryButton(
                text: _accepting ? 'Accepting...' : 'Accept delivery',
                onPressed: _accepting ? null : _accept,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
