import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/rider_record.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/rider_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class RiderDetailScreen extends StatefulWidget {
  final String riderId;
  final RiderApi? riderApi;
  const RiderDetailScreen({super.key, required this.riderId, this.riderApi});

  @override
  State<RiderDetailScreen> createState() => _RiderDetailScreenState();
}

class _RiderDetailScreenState extends State<RiderDetailScreen> {
  late final RiderApi _api = widget.riderApi ?? RiderApi(ApiClient());
  Future<RiderRecord>? _future;
  bool _mutating = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<RiderRecord> _load() async {
    final json = await _api.getById(widget.riderId);
    return RiderRecord.fromJson(json);
  }

  Future<void> _toggleSuspension(RiderStatus current) async {
    setState(() => _mutating = true);
    try {
      final nextSuspended = current != RiderStatus.suspended;
      await _api.setSuspended(widget.riderId, nextSuspended);
      _changed = true;
      if (!mounted) return;
      setState(() => _future = _load());
      await _future;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nextSuspended ? 'Account suspended' : 'Account reactivated')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update rider: $err')));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Rider')),
        body: FutureBuilder<RiderRecord>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Failed to load rider: ${snapshot.error}'));
            }
            final r = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppComponents.cardDecoration(),
                  child: Column(
                    children: [
                      _row("ID", r.id),
                      _row("Name", r.name),
                      _row("Email", r.email),
                      _row("Loyalty member", r.isLoyaltyMember ? "Yes" : "No"),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                AppComponents.sectionTitle("Recent trips"),
                if (r.recentTrips == null || r.recentTrips!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("No trips yet.", style: TextStyle(color: Colors.black54)),
                  )
                else
                  ...r.recentTrips!.map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: AppComponents.cardDecoration(),
                          child: Row(
                            children: [
                              Expanded(child: Text('${t.pickup} → ${t.destination}', style: const TextStyle(fontSize: 13))),
                              AppComponents.badge(t.status),
                            ],
                          ),
                        ),
                      )),
                const SizedBox(height: 20),
                AppComponents.outlineButton(
                  text: _mutating ? "Working…" : (r.status == RiderStatus.suspended ? "Reactivate account" : "Suspend account"),
                  color: r.status == RiderStatus.suspended ? AppColors.success : AppColors.danger,
                  onPressed: _mutating ? null : () => _toggleSuspension(r.status),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
