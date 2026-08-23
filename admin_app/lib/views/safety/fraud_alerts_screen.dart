import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/fraud_alert.dart';
import 'package:ravelgo_admin/services/api/alerts_api.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class FraudAlertsScreen extends StatefulWidget {
  final AlertsApi? alertsApi;
  const FraudAlertsScreen({super.key, this.alertsApi});

  @override
  State<FraudAlertsScreen> createState() => _FraudAlertsScreenState();
}

class _FraudAlertsScreenState extends State<FraudAlertsScreen> {
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
    return raw.map(EmergencyAlertRecord.fromJson).where((a) => a.type == 'FRAUD_SUSPECTED').toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _advance(EmergencyAlertRecord alert, String status) async {
    setState(() => _mutatingIds.add(alert.id));
    try {
      await _api.setStatus(alert.id, status);
      if (!mounted) return;
      await _refresh();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update alert: $err')));
    } finally {
      if (mounted) setState(() => _mutatingIds.remove(alert.id));
    }
  }

  Color _statusColor(AlertStatus s) {
    switch (s) {
      case AlertStatus.open:
        return AppColors.danger;
      case AlertStatus.acknowledged:
        return AppColors.warning;
      case AlertStatus.resolved:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Fraud Alerts")),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<EmergencyAlertRecord>>(
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
                "Fraud-suspected reports raised by riders/drivers via the app's emergency-alert flow.",
                style: TextStyle(fontSize: 12.5),
              ),
            );
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  banner,
                  Center(child: Text('Failed to load alerts: ${snapshot.error}', textAlign: TextAlign.center)),
                  const SizedBox(height: 12),
                  Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
                ],
              );
            }
            final alerts = snapshot.data ?? const [];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                banner,
                if (alerts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('No fraud alerts.', style: TextStyle(color: Colors.black54))),
                  ),
                ...alerts.map((a) {
                  final mutating = _mutatingIds.contains(a.id);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: AppComponents.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text('${a.personName} (${a.role})', style: const TextStyle(fontWeight: FontWeight.w700))),
                            AppComponents.badge(a.status.name, color: _statusColor(a.status)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(a.message ?? 'No additional details provided.', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                        const SizedBox(height: 6),
                        Text(formatFriendlyDate(a.createdAt), style: const TextStyle(fontSize: 11, color: Colors.black45)),
                        if (a.status != AlertStatus.resolved) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              if (a.status == AlertStatus.open)
                                Expanded(
                                  child: AppComponents.outlineButton(
                                    text: mutating ? "…" : "Acknowledge",
                                    onPressed: mutating ? null : () => _advance(a, 'ACKNOWLEDGED'),
                                  ),
                                ),
                              if (a.status == AlertStatus.open) const SizedBox(width: 10),
                              Expanded(
                                child: AppComponents.outlineButton(
                                  text: mutating ? "…" : "Resolve",
                                  color: AppColors.danger,
                                  onPressed: mutating ? null : () => _advance(a, 'RESOLVED'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}
