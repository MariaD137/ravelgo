import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/Model/ride_lifecycle.dart';
import 'package:ravelgo_user_app/views/HomeView/Home.dart';
import 'package:ravelgo_user_app/views/TexiModule/RiderTripScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Driver offers for the rider's request.
/// - Accept -> enters the accepted-driver trip lifecycle (RiderTripScreen).
/// - Decline -> removes that offer; declining all offers returns the rider
///   to the search state instead of leaving a dead screen.
/// Offers are demo data until the matching backend is connected.
class RequestDriverScreen extends StatefulWidget {
  const RequestDriverScreen({super.key});

  @override
  State<RequestDriverScreen> createState() => _RequestDriverScreenState();
}

class _RequestDriverScreenState extends State<RequestDriverScreen> {
  final List<RideOffer> _offers = [
    const RideOffer(
        driverName: 'Thelma Ibeh',
        vehicle: 'Toyota Corolla',
        rating: 4.55,
        fare: 'NGN 7,000',
        etaMinutes: 10,
        avatarAsset: 'assets/ic_avatar1.png'),
    const RideOffer(
        driverName: 'Chidi Eze',
        vehicle: 'Honda Accord',
        rating: 4.8,
        fare: 'NGN 6,500',
        etaMinutes: 7,
        avatarAsset: 'assets/ic_avatar2.png'),
    const RideOffer(
        driverName: 'Amaka Obi',
        vehicle: 'Kia Cerato',
        rating: 4.7,
        fare: 'NGN 7,200',
        etaMinutes: 12,
        avatarAsset: 'assets/ic_avatar3.png'),
  ];

  void _accept(RideOffer offer) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => RiderTripScreen(offer: offer)),
    );
  }

  void _decline(RideOffer offer) {
    setState(() => _offers.remove(offer));
    if (_offers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All offers declined - keep searching for drivers')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              color: AppColors.surfaceElevated,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Found ${_offers.length} Driver${_offers.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      const Text("Pick one, and let's hit the road", style: TextStyle(fontSize: 13)),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const HomePage()),
                      );
                    },
                    child: const Text(
                      'Cancel trip',
                      style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Driver offers
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _offers.length,
                itemBuilder: (context, index) {
                  final offer = _offers[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: DriverCard(
                      offer: offer,
                      onAccept: () => _accept(offer),
                      onDecline: () => _decline(offer),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DriverCard extends StatelessWidget {
  final RideOffer offer;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const DriverCard({super.key, required this.offer, required this.onAccept, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Driver row
            Row(
              children: [
                CircleAvatar(radius: 30, backgroundImage: AssetImage(offer.avatarAsset)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(offer.driverName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(offer.vehicle,
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.star, color: AppColors.success, size: 16),
                          const SizedBox(width: 4),
                          Text('${offer.rating} Rating',
                              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.verified, color: AppColors.primary),
              ],
            ),
            const SizedBox(height: 12),

            // Fare and distance
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(offer.fare, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const Expanded(child: Divider(thickness: 1, color: AppColors.border)),
                Text('${offer.etaMinutes} mins away', style: const TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDecline,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
