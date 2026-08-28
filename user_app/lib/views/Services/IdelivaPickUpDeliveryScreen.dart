import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views/HomeView/scheduled_rides_screen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class PickDeliveryScreen extends StatelessWidget {
  final List<Map<String, String>> deliveryRequests = [
    {
      'pickup': 'Denco court 1',
      'drop': 'Lekki',
      'fare': 'NGN 8,000',
      'time': '14:30',
    },
    {
      'pickup': 'Denco court 1',
      'drop': 'Lekki',
      'fare': 'NGN 8,000',
      'time': '14:30',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App Bar
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  SizedBox(width: 4),
                  Text(
                    "Pick a delivery",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ScheduledRidesRequestsScreen(),
                        ),
                      );
                    },
                    child: Row(
                      children: const [
                        Icon(Icons.calendar_month, color: AppColors.success),
                        SizedBox(width: 4),
                        Text(
                          "Scheduled requests",
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              SizedBox(height: 20),

              Text(
                "Delivery requests",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),

              SizedBox(height: 10),

              // Delivery Requests List
              Expanded(
                child: ListView.separated(
                  itemCount: deliveryRequests.length,
                  separatorBuilder: (_, __) => SizedBox(height: 20),
                  itemBuilder: (context, index) {
                    final item = deliveryRequests[index];
                    return Container(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Delivery time – ${item['time']}",
                            style: TextStyle(
                              color: Colors.brown[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text("Route", style: TextStyle(fontWeight: FontWeight.w600)),
                          SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.radio_button_checked, color: AppColors.success),
                              SizedBox(width: 8),
                              Text(item['pickup'] ?? ""),
                            ],
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.percent, color: Colors.brown),
                              SizedBox(width: 8),
                              Text(item['drop'] ?? ""),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            "Delivery fare: ${item['fare']}",
                            style: TextStyle(
                              color: Colors.brown[800],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Delivery accepted - the sender has been notified')),
                                    );
                                    Navigator.pop(context);
                                  },
                                  child: Text(
                                    "Accept",
                                    style: TextStyle(color: AppColors.textPrimary),
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: AppColors.error),
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Delivery request declined')),
                                    );
                                    Navigator.pop(context);
                                  },
                                  child: Text(
                                    "Decline",
                                    style: TextStyle(color: AppColors.error),
                                  ),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}