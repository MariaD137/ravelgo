import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'RidesView.dart'; // adjust path if needed; this imports the Ride class
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/AccountView/EReceiptPage.dart';

class RideDetailsScreen extends StatelessWidget {
  final Ride ride;

  const RideDetailsScreen({Key? key, required this.ride}) : super(key: key);

  String _formatTime(DateTime dt) {
    final months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'pm' : 'am';
    return '${dt.day} ${months[dt.month]}. $hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
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
                            ride.driverName != null && ride.driverName!.isNotEmpty
                                ? 'Ride with ${ride.driverName}'
                                : 'Trip to ${ride.destination.isNotEmpty ? ride.destination : ride.title}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(_formatTime(ride.dateTime), style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Map preview
            SizedBox(
              height: 300,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset("assets/fake_map.png",fit: BoxFit.fill,),
                  ),
                  // Positioned(
                  //   right: 12,
                  //   bottom: 12,
                  //   child: Material(
                  //     elevation: 2,
                  //     shape: const CircleBorder(),
                  //     color: AppColors.surface,
                  //     child: IconButton(
                  //       icon: const Icon(Icons.my_location),
                  //       onPressed: () {},
                  //     ),
                  //   ),
                  // ),
                ],
              ),
            ),

            // Details & payments (static example)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Real pickup -> destination for this trip.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // timeline indicator
                        Column(
                          children: [
                            Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green)),
                            Container(width: 2, height: 48, color: AppColors.border),
                            Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.textMuted)),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ride.pickup.isNotEmpty ? ride.pickup : 'Pickup',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 48),
                              Text(ride.destination.isNotEmpty ? ride.destination : 'Destination',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),
                    const Text('Payments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),

                    _paymentRow('Ride Fare', Currency.format(ride.fare)),
                    const Divider(height: 22, color: AppColors.textMuted),

                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        children: [
                          const Expanded(child: Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                          Text(Currency.format(ride.fare), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const EReceiptPage()),
                      ),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('View E-Receipt'),
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

  Widget _paymentRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: AppColors.textSecondary))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}