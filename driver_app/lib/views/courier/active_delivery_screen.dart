import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';

enum _DeliveryStage { headingToPickup, inTransit }

/// Step 3 of the real driver courier flow: Pickup -> In Transit -> Delivered,
/// each step a real PATCH /api/courier-requests/:id/status call against the
/// backend (not a local-only stage flag). Reaching DELIVERED releases the
/// driver's DriverAssignment row server-side (services/courier.ts's
/// updateCourierStatus), which is what actually frees them for a new ride,
/// courier request, or rental — this screen's own state is just a mirror of
/// that, reconciled via DriverSession.reconcile after each call.
class ActiveDeliveryScreen extends StatefulWidget {
  const ActiveDeliveryScreen({super.key, required this.request});

  final Map<String, dynamic> request;

  @override
  State<ActiveDeliveryScreen> createState() => _ActiveDeliveryScreenState();
}

class _ActiveDeliveryScreenState extends State<ActiveDeliveryScreen> {
  _DeliveryStage _stage = _DeliveryStage.headingToPickup;
  bool _submitting = false;

  String get _requestId => widget.request['id'] as String;

  Future<void> _confirmPickup() async {
    setState(() => _submitting = true);
    try {
      await DriverSession.instance.courierApi.updateStatus(_requestId, 'IN_TRANSIT');
      if (!mounted) return;
      setState(() {
        _stage = _DeliveryStage.inTransit;
        _submitting = false;
      });
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
    }
  }

  Future<void> _markDelivered() async {
    setState(() => _submitting = true);
    try {
      await DriverSession.instance.courierApi.updateStatus(_requestId, 'DELIVERED');
      DriverSession.instance.reconcile(busy: false);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DriverShell()),
        (route) => false,
      );
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final isPickupStage = _stage == _DeliveryStage.headingToPickup;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            AppComponents.header(context, 'Active delivery'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: AppComponents.cardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isPickupStage ? Icons.inventory_2_outlined : Icons.local_shipping_outlined,
                                color: AppColors.primaryDark,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isPickupStage ? 'Heading to pickup' : 'In transit to recipient',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isPickupStage ? (r['pickupAddress'] as String? ?? '') : (r['dropoffAddress'] as String? ?? ''),
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 12),
                          Text('Recipient: ${r['recipientName']}'),
                          Text('Phone: ${r['recipientPhone']}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppComponents.primaryButton(
                text: _submitting
                    ? 'Updating...'
                    : (isPickupStage ? 'Confirm pickup' : 'Mark delivered'),
                onPressed: _submitting ? null : (isPickupStage ? _confirmPickup : _markDelivered),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
