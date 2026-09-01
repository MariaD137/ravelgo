import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/rider_record.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class RiderDetailScreen extends StatefulWidget {
  final RiderRecord rider;
  const RiderDetailScreen({super.key, required this.rider});

  @override
  State<RiderDetailScreen> createState() => _RiderDetailScreenState();
}

class _RiderDetailScreenState extends State<RiderDetailScreen> {
  late RiderStatus _status;

  @override
  void initState() {
    super.initState();
    _status = widget.rider.status;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rider;
    return Scaffold(
      appBar: AppBar(title: Text(r.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              children: [
                _row("ID", r.id),
                _row("Email", r.email),
                _row("Total trips", "${r.totalTrips}"),
                _row("Rating given by drivers", "★ ${r.rating}"),
                _row("Loyalty member", r.isLoyaltyMember ? "Yes" : "No"),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppComponents.outlineButton(
            text: _status == RiderStatus.suspended ? "Reactivate account" : "Suspend account",
            color: _status == RiderStatus.suspended ? AppColors.success : AppColors.danger,
            onPressed: () => setState(() {
              _status = _status == RiderStatus.suspended ? RiderStatus.active : RiderStatus.suspended;
            }),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
