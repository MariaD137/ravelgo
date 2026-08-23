import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/car_paddy_request.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/carpaddy_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class CarPaddyRequestsScreen extends StatefulWidget {
  final CarPaddyApi? carPaddyApi;
  const CarPaddyRequestsScreen({super.key, this.carPaddyApi});

  @override
  State<CarPaddyRequestsScreen> createState() => _CarPaddyRequestsScreenState();
}

class _CarPaddyRequestsScreenState extends State<CarPaddyRequestsScreen> {
  late final CarPaddyApi _api = widget.carPaddyApi ?? CarPaddyApi(ApiClient());
  late Future<List<CarPaddyRequest>> _future;
  final Set<String> _mutatingIds = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CarPaddyRequest>> _load() async {
    final raw = await _api.listAll();
    return raw.map(CarPaddyRequest.fromJson).toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _decide(CarPaddyRequest request, String status) async {
    setState(() => _mutatingIds.add(request.id));
    try {
      await _api.decide(request.id, status);
      if (!mounted) return;
      await _refresh();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update request: $err')));
    } finally {
      if (mounted) setState(() => _mutatingIds.remove(request.id));
    }
  }

  Color _statusColor(CarPaddyStatus s) {
    switch (s) {
      case CarPaddyStatus.submitted:
        return Colors.grey;
      case CarPaddyStatus.inReview:
        return AppColors.warning;
      case CarPaddyStatus.approved:
        return AppColors.success;
      case CarPaddyStatus.rejected:
        return AppColors.danger;
    }
  }

  String _statusLabel(CarPaddyStatus s) {
    switch (s) {
      case CarPaddyStatus.submitted:
        return "Submitted";
      case CarPaddyStatus.inReview:
        return "In review";
      case CarPaddyStatus.approved:
        return "Approved";
      case CarPaddyStatus.rejected:
        return "Rejected";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Car Paddy Requests")),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<CarPaddyRequest>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Failed to load requests: ${snapshot.error}', textAlign: TextAlign.center)),
                  const SizedBox(height: 12),
                  Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
                ],
              );
            }
            final requests = snapshot.data ?? const [];
            if (requests.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No Car Paddy requests yet.', style: TextStyle(color: Colors.black54))),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = requests[i];
                final mutating = _mutatingIds.contains(r.id);
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppComponents.cardDecoration(),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("${r.driverName} · ${r.plateNumber}", style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text("Submitted ${formatShortDate(r.submittedOn)}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                      if (mutating)
                        const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                      else if (r.status == CarPaddyStatus.inReview || r.status == CarPaddyStatus.submitted)
                        Row(
                          children: [
                            IconButton(icon: const Icon(Icons.close, color: AppColors.danger), onPressed: () => _decide(r, 'REJECTED')),
                            IconButton(icon: const Icon(Icons.check, color: AppColors.success), onPressed: () => _decide(r, 'APPROVED')),
                          ],
                        )
                      else
                        AppComponents.badge(_statusLabel(r.status), color: _statusColor(r.status)),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
