import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/driver_record.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class DriverDetailScreen extends StatefulWidget {
  final DriverRecord driver;
  const DriverDetailScreen({super.key, required this.driver});

  @override
  State<DriverDetailScreen> createState() => _DriverDetailScreenState();
}

class _DriverDetailScreenState extends State<DriverDetailScreen> {
  late DriverStatus _status;

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
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(doc.$1),
                                  content: const Text(
                                      'Document preview requires the document-storage service, '
                                      'which is not connected in this build. Use the driver\'s '
                                      'submitted files once storage is wired.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('OK')),
                                  ],
                                ),
                              );
                            },
                            child: const Text("Review")),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: AppComponents.outlineButton(
                  text: _status == DriverStatus.suspended ? "Reactivate" : "Suspend driver",
                  color: _status == DriverStatus.suspended ? AppColors.success : AppColors.danger,
                  onPressed: () => setState(() {
                    _status = _status == DriverStatus.suspended ? DriverStatus.active : DriverStatus.suspended;
                  }),
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
