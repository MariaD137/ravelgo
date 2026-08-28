import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views/RideView/RideDetailsView.dart';
import 'RideDetailsView.dart'; // adjust path if needed
import 'package:ravelgo_user_app/theme/app_theme.dart';

class Ride {
  final DateTime dateTime;
  final String title;
  final String id;

  Ride({required this.dateTime, required this.title, required this.id});
}

class RidesView extends StatelessWidget {
  RidesView({Key? key}) : super(key: key);

  // SAMPLE DATA: grouped by "Month Year" string
  final Map<String, List<Ride>> ridesByMonth = {
    'March 2025': [
      Ride(dateTime: DateTime(2025, 3, 16, 12, 11), title: 'Denco court 1', id: '#2444'),
      Ride(dateTime: DateTime(2025, 3, 15, 9, 30), title: 'Denco court 1', id: '#2443'),
      Ride(dateTime: DateTime(2025, 3, 14, 18, 45), title: 'Denco court 2', id: '#2442'),
    ],
    'January 2025': [
      Ride(dateTime: DateTime(2025, 1, 21, 11, 5), title: 'Denco court 1', id: '#2331'),
      Ride(dateTime: DateTime(2025, 1, 10, 14, 20), title: 'Denco court 3', id: '#2309'),
    ],
  };

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
    final List<Widget> children = [];

    ridesByMonth.forEach((month, rides) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Text(
          month,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ));

      for (var i = 0; i < rides.length; i++) {
        final ride = rides[i];

        children.add(Column(
          children: [
            // LIST TILE: now tappable and navigates to RideDetailsScreen
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              leading: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.directions_car, color: AppColors.textSecondary),
              ),
              title: Text(
                ride.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatTime(ride.dateTime),
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ride.id,
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              onTap: () {
                // Navigate to details screen and pass the selected ride
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RideDetailsScreen(ride: ride),
                  ),
                );
              },
            ),

            // thin divider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Divider(height: 1, color: AppColors.border),
            ),
          ],
        ));
      }
    });

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(

        child: Column(
          children: [
            // Top appbar area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Ride history',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.info_outline, size: 24),
                    onPressed: () {
                      // show info or help
                    },
                  ),
                ],
              ),
            ),

            // The listing
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}