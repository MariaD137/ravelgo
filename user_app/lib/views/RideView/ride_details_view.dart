import 'package:flutter/material.dart';
import 'rides_view.dart';

class RideDetailsScreen extends StatelessWidget {
  final Ride ride;

  const RideDetailsScreen({super.key, required this.ride});

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
    // You can replace this image with a live map widget (GoogleMap) when ready

    return Scaffold(
      backgroundColor: Colors.white,
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
                        Text('Ride with ${ride.title}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(_formatTime(ride.dateTime), style: TextStyle(fontSize: 13, color: Colors.grey[600])),
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
                  //     color: Colors.white,
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
                    // Example stops (replace with real stops if available)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // timeline indicator
                        Column(
                          children: [
                            Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green)),
                            Container(width: 2, height: 48, color: Colors.grey.shade300),
                            Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('24 kusenla road', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              SizedBox(height: 12),
                              Text('Dutse', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              SizedBox(height: 12),
                              Text('Madiba', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    const Text(
                      'Additional ride details can be found in your email receipt',
                      style: TextStyle(color: Color(0xFF7A5F00)),
                    ),

                    const SizedBox(height: 18),
                    const Text('Payments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),

                    _paymentRow('Ride Fare', '#2854'),
                    const Divider(height: 18, color: Colors.grey),
                    _paymentRow('Vat Fees', '#52.50'),
                    const Divider(height: 22, color: Colors.grey),

                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        children: const [
                          Expanded(child: Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                          Text('#2854', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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

  Widget _paymentRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: Colors.grey[700]))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

}