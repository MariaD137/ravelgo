import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class CourierRequestsScreen extends StatefulWidget {
  const CourierRequestsScreen({super.key});

  @override
  State<CourierRequestsScreen> createState() => _CourierRequestsScreenState();
}

class _CourierRequestsScreenState extends State<CourierRequestsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient().get('/courier-requests');
      final page = response as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _requests = List<Map<String, dynamic>>.from(page['data'] ?? []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'AWAITING_COURIER':
        return 'Awaiting courier';
      case 'IN_TRANSIT':
        return 'In transit';
      case 'DELIVERED':
        return 'Delivered';
      case 'CANCELLED':
        return 'Cancelled';
      default:
        return status ?? 'Unknown';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'AWAITING_COURIER':
        return AppColors.warning;
      case 'IN_TRANSIT':
        return AppColors.info;
      case 'DELIVERED':
        return AppColors.success;
      case 'CANCELLED':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _requesterName(Map<String, dynamic> c) {
    final requester = c['requester'] as Map<String, dynamic>?;
    if (requester == null) return c['requesterName'] as String? ?? 'Unknown';
    return '${requester['firstName'] ?? ''} ${requester['lastName'] ?? ''}'.trim();
  }

  String? _courierName(Map<String, dynamic> c) {
    final courier = c['courier'] as Map<String, dynamic>?;
    if (courier == null) return c['courierName'] as String?;
    final name = '${courier['firstName'] ?? ''} ${courier['lastName'] ?? ''}'.trim();
    return name.isEmpty ? null : name;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Be a Courier — Requests")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Be a Courier — Requests")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                const Text('Failed to load courier requests', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () { setState(() { _loading = true; _error = null; }); _loadData(); },
                  child: const Text("Retry"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Be a Courier — Requests")),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: const Text(
                "Couriers are Riders using the Be a Courier feature. RavelGo charges a fixed fee per request, separate from the courier's negotiated fare.",
                style: TextStyle(fontSize: 12.5),
              ),
            ),
            if (_requests.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text("No courier requests", style: TextStyle(color: Colors.black54))),
              )
            else
              ..._requests.map((c) {
                final status = c['status'] as String?;
                final pickup = c['pickupStation'] as String? ?? c['pickup'] as String? ?? '';
                final dropoff = c['dropoffStation'] as String? ?? c['destination'] as String? ?? '';
                final fixedFee = (c['fixedFee'] ?? c['platformFee'] ?? 0).toDouble();
                final courierFare = (c['courierFare'] ?? c['fare'] ?? 0).toDouble();
                final id = c['id'] as String? ?? '';
                final courierName = _courierName(c);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AppComponents.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(id, style: const TextStyle(fontWeight: FontWeight.w700)),
                            AppComponents.badge(_statusLabel(status), color: _statusColor(status)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text("$pickup → $dropoff", style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 6),
                        Text(
                          "Requested by ${_requesterName(c)}${courierName != null ? ' · Courier: $courierName' : ''}",
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("RavelGo fee: ₦${fixedFee.toStringAsFixed(0)}", style: const TextStyle(fontSize: 12)),
                            Text("Courier fare: ₦${courierFare.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
