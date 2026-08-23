import 'package:flutter/material.dart';
import 'RidesView.dart' show formatTripTime;

/// The real receipt for one past trip — every field here comes from the
/// Trip row GET /api/trips/mine returned (pickup/destination/status/fare/
/// driver), not a static example. There is no per-trip VAT/fee breakdown
/// in the backend's Payment model — only a total amount — so this screen
/// shows the total fare it actually has rather than inventing a breakdown.
class RideDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> trip;

  const RideDetailsScreen({Key? key, required this.trip}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final requestedAt = DateTime.tryParse(trip['requestedAt'] as String? ?? '');
    final driver = trip['driver'] as Map<String, dynamic>?;
    final driverUser = driver?['user'] as Map<String, dynamic>?;
    final driverName = driverUser != null ? '${driverUser['firstName']} ${driverUser['lastName']}' : null;
    final fare = (trip['finalFare'] as num?) ?? (trip['estimatedFare'] as num?);
    final isEstimate = trip['finalFare'] == null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driverName != null ? 'Ride with $driverName' : 'Ride ${trip['status']}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        if (requestedAt != null) ...[
                          const SizedBox(height: 4),
                          Text(formatTripTime(requestedAt), style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(width: 14, height: 14, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green)),
                            Container(width: 2, height: 36, color: Colors.grey.shade300),
                            Container(width: 14, height: 14, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent)),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(trip['pickup'] as String? ?? '—', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 20),
                              Text(trip['destination'] as String? ?? '—', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text('Status: ${trip['status']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 18),
                    const Text('Fare', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              isEstimate ? 'Estimated total' : 'Total',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            fare != null ? '₦${fare.toStringAsFixed(0)}' : '—',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
