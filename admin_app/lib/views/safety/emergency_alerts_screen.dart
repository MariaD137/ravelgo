import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/fraud_alert.dart';
import 'package:ravelgo_admin/services/api/alerts_api.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class EmergencyAlertsScreen extends StatefulWidget {
  final AlertsApi? alertsApi;
  const EmergencyAlertsScreen({super.key, this.alertsApi});

  @override
  State<EmergencyAlertsScreen> createState() => _EmergencyAlertsScreenState();
}

class _EmergencyAlertsScreenState extends State<EmergencyAlertsScreen> {
  late final AlertsApi _api = widget.alertsApi ?? AlertsApi(ApiClient());
  late Future<List<EmergencyAlertRecord>> _future;
  final Set<String> _mutatingIds = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<EmergencyAlertRecord>> _load() async {
    final raw = await _api.listAll(pageSize: 50);
    return raw.map(EmergencyAlertRecord.fromJson).where((a) => a.type == 'SOS').toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _resolve(EmergencyAlertRecord alert) async {
    setState(() => _mutatingIds.add(alert.id));
    try {
      await _api.setStatus(alert.id, 'RESOLVED');
      if (!mounted) return;
      await _refresh();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update alert: $err')));
    } finally {
      if (mounted) setState(() => _mutatingIds.remove(alert.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Emergency Alerts")),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<EmergencyAlertRecord>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Failed to load alerts: ${snapshot.error}', textAlign: TextAlign.center)),
                  const SizedBox(height: 12),
                  Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
                ],
              );
            }
            final alerts = snapshot.data ?? const [];
            if (alerts.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No SOS alerts.', style: TextStyle(color: Colors.black54))),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: alerts.map((e) {
                final mutating = _mutatingIds.contains(e.id);
                final resolved = e.status == AlertStatus.resolved;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: AppComponents.cardDecoration(),
                  child: Row(
                    children: [
                      Icon(Icons.sos, color: resolved ? Colors.grey : AppColors.danger, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("${e.personName} (${e.role})", style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(e.message ?? 'No additional details provided.', style: const TextStyle(fontSize: 12.5)),
                            const SizedBox(height: 2),
                            Text(formatFriendlyDate(e.createdAt), style: const TextStyle(fontSize: 11, color: Colors.black45)),
                          ],
                        ),
                      ),
                      if (resolved)
                        AppComponents.badge("Resolved", color: AppColors.success)
                      else
                        ElevatedButton(
                          onPressed: mutating ? null : () => _resolve(e),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
                          child: Text(mutating ? '…' : 'Mark resolved'),
                        ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}
