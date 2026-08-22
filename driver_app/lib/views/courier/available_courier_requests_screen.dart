import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/courier/courier_request_details_screen.dart';

/// Step 1 of the real driver courier flow: lists unassigned courier
/// requests from the actual backend (GET /api/courier-requests/available),
/// not mock/demo data. See courier_request_details_screen.dart and
/// active_delivery_screen.dart for the rest of the flow.
class AvailableCourierRequestsScreen extends StatefulWidget {
  const AvailableCourierRequestsScreen({super.key});

  @override
  State<AvailableCourierRequestsScreen> createState() => _AvailableCourierRequestsScreenState();
}

class _AvailableCourierRequestsScreenState extends State<AvailableCourierRequestsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return DriverSession.instance.courierApi.listAvailable();
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            AppComponents.header(context, 'Available deliveries'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      final message = snapshot.error is ApiException
                          ? (snapshot.error as ApiException).message
                          : 'Could not load delivery requests.';
                      return ListView(
                        children: [
                          const SizedBox(height: 80),
                          Icon(Icons.error_outline, size: 40, color: AppColors.danger),
                          const SizedBox(height: 12),
                          Center(child: Text(message, textAlign: TextAlign.center)),
                        ],
                      );
                    }
                    final requests = snapshot.data ?? const [];
                    if (requests.isEmpty) {
                      return ListView(
                        children: const [
                          SizedBox(height: 80),
                          Center(child: Text('No delivery requests available right now.')),
                        ],
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: requests.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final r = requests[index];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: AppComponents.cardDecoration(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r['packageDescription'] as String? ?? 'Package',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              const SizedBox(height: 6),
                              Text('Pickup: ${r['pickupAddress']}', style: const TextStyle(color: Colors.black54)),
                              Text('Dropoff: ${r['dropoffAddress']}', style: const TextStyle(color: Colors.black54)),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '₦${r['estimatedFare']}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CourierRequestDetailsScreen(request: r),
                                        ),
                                      );
                                      if (context.mounted) await _refresh();
                                    },
                                    child: const Text('View details'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
