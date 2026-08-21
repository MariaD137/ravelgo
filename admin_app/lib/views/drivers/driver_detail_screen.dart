import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/driver_record.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class DriverDetailScreen extends StatefulWidget {
  final DriverRecord driver;
  const DriverDetailScreen({super.key, required this.driver});

  @override
  State<DriverDetailScreen> createState() => _DriverDetailScreenState();
}

class _DriverDetailScreenState extends State<DriverDetailScreen> {
  late DriverStatus _status;
  bool _togglingStatus = false;

  static const _documents = [
    ("Driver's License", true),
    ("Vehicle Registration (Car Papers)", true),
    ("Roadworthiness Certificate", true),
    ("Insurance Certificate", false),
    ("Background Check", true),
  ];

  @override
  void initState() {
    super.initState();
    _status = widget.driver.status;
  }

  Future<void> _toggleStatus() async {
    final newStatus = _status == DriverStatus.suspended ? 'ACTIVE' : 'SUSPENDED';
    setState(() => _togglingStatus = true);
    try {
      await ApiClient().patch('/drivers/${widget.driver.id}/status', body: {'status': newStatus});
      if (!mounted) return;
      setState(() {
        _status = newStatus == 'SUSPENDED' ? DriverStatus.suspended : DriverStatus.active;
        _togglingStatus = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Driver ${newStatus == "SUSPENDED" ? "suspended" : "reactivated"} successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _togglingStatus = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.driver;
    return Scaffold(
      appBar: AppBar(title: Text(d.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("ID"),
                    Text(d.id, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Email"),
                    Text(d.email, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Vehicle"),
                    Text(d.vehicle, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Rating"),
                    Text("★ ${d.rating}  ·  ${d.totalTrips} trips", style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Subscription"),
                    AppComponents.badge(d.subscriptionActive ? "Active" : "Inactive", color: d.subscriptionActive ? AppColors.success : AppColors.danger),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppComponents.sectionTitle("Document verification"),
          ..._documents.map((doc) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: AppComponents.cardDecoration(),
                  child: Row(
                    children: [
                      Icon(doc.$2 ? Icons.check_circle : Icons.pending_outlined, color: doc.$2 ? AppColors.success : AppColors.warning, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(doc.$1, style: const TextStyle(fontSize: 13.5))),
                      if (!doc.$2)
                        TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Feature coming soon')),
                            );
                          },
                          child: const Text("Review"),
                        ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: AppComponents.outlineButton(
                  text: _togglingStatus
                      ? 'Updating...'
                      : (_status == DriverStatus.suspended ? "Reactivate" : "Suspend driver"),
                  color: _status == DriverStatus.suspended ? AppColors.success : AppColors.danger,
                  onPressed: _togglingStatus ? null : _toggleStatus,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppComponents.primaryButton(
                  text: "Approve documents",
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("All documents approved")),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
