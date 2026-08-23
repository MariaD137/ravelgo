import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/courier_request.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/courier_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class CourierRequestsScreen extends StatefulWidget {
  final CourierApi? courierApi;
  const CourierRequestsScreen({super.key, this.courierApi});

  @override
  State<CourierRequestsScreen> createState() => _CourierRequestsScreenState();
}

class _CourierRequestsScreenState extends State<CourierRequestsScreen> {
  late final CourierApi _api = widget.courierApi ?? CourierApi(ApiClient());
  late Future<List<CourierRequest>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CourierRequest>> _load() async {
    final raw = await _api.listAll();
    return raw.map(CourierRequest.fromJson).toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Color _statusColor(CourierRequestStatus s) {
    switch (s) {
      case CourierRequestStatus.awaitingCourier:
        return AppColors.warning;
      case CourierRequestStatus.inTransit:
        return AppColors.info;
      case CourierRequestStatus.delivered:
        return AppColors.success;
      case CourierRequestStatus.cancelled:
        return Colors.grey;
    }
  }

  String _statusLabel(CourierRequestStatus s) {
    switch (s) {
      case CourierRequestStatus.awaitingCourier:
        return "Awaiting courier";
      case CourierRequestStatus.inTransit:
        return "In transit";
      case CourierRequestStatus.delivered:
        return "Delivered";
      case CourierRequestStatus.cancelled:
        return "Cancelled";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Be a Courier — Requests")),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<CourierRequest>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final banner = Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: const Text(
                "Couriers are Riders using the Be a Courier feature.",
                style: TextStyle(fontSize: 12.5),
              ),
            );
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  banner,
                  Center(child: Text('Failed to load courier requests: ${snapshot.error}', textAlign: TextAlign.center)),
                  const SizedBox(height: 12),
                  Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
                ],
              );
            }
            final requests = snapshot.data ?? const [];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                banner,
                if (requests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('No courier requests yet.', style: TextStyle(color: Colors.black54))),
                  ),
                ...requests.map((c) => Padding(
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
                                Expanded(child: Text(c.id, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                                AppComponents.badge(_statusLabel(c.status), color: _statusColor(c.status)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text("${c.pickupStation} → ${c.dropoffStation}", style: const TextStyle(fontSize: 13)),
                            const SizedBox(height: 6),
                            Text("Requested by ${c.requesterName}${c.courierName != null ? ' · Courier: ${c.courierName}' : ''}",
                                style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text("Fare: ₦${c.courierFare.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    )),
              ],
            );
          },
        ),
      ),
    );
  }
}
