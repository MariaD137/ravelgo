import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class FraudAlertsScreen extends StatefulWidget {
  const FraudAlertsScreen({super.key});

  @override
  State<FraudAlertsScreen> createState() => _FraudAlertsScreenState();
}

class _FraudAlertsScreenState extends State<FraudAlertsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _alerts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient().get('/emergency-alerts');
      final page = response as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _alerts = List<Map<String, dynamic>>.from(page['data'] ?? []);
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

  Future<void> _dismissAlert(String id, int index) async {
    try {
      await ApiClient().patch('/emergency-alerts/$id', body: {'status': 'RESOLVED'});
      if (!mounted) return;
      setState(() {
        _alerts.removeAt(index);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert dismissed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to dismiss alert: $e')),
      );
    }
  }

  Color _severityColor(String? severity) {
    switch (severity?.toUpperCase()) {
      case 'LOW':
        return AppColors.success;
      case 'MEDIUM':
        return AppColors.warning;
      case 'HIGH':
        return AppColors.danger;
      default:
        return Colors.grey;
    }
  }

  String _severityLabel(String? severity) {
    switch (severity?.toUpperCase()) {
      case 'LOW':
        return 'low';
      case 'MEDIUM':
        return 'medium';
      case 'HIGH':
        return 'high';
      default:
        return severity ?? 'unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Safety Alerts")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Safety Alerts")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                const Text('Failed to load alerts', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
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
      appBar: AppBar(title: const Text("Safety Alerts")),
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
                "Safety alerts flag unusual booking patterns or ride behavior for your review.",
                style: TextStyle(fontSize: 12.5),
              ),
            ),
            if (_alerts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text("No alerts", style: TextStyle(color: Colors.black54))),
              )
            else
              ..._alerts.asMap().entries.map((entry) {
                final index = entry.key;
                final a = entry.value;
                final id = a['id'] as String? ?? '';
                final title = a['title'] as String? ?? a['message'] as String? ?? 'Alert';
                final description = a['description'] as String? ?? a['details'] as String? ?? '';
                final severity = a['severity'] as String? ?? a['level'] as String?;
                final detectedAt = a['createdAt'] != null
                    ? DateTime.tryParse(a['createdAt'].toString()) ?? DateTime.now()
                    : DateTime.now();

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
                          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
                          AppComponents.badge(_severityLabel(severity), color: _severityColor(severity)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(description, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                      const SizedBox(height: 6),
                      Text(formatFriendlyDate(detectedAt), style: const TextStyle(fontSize: 11, color: Colors.black45)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: AppComponents.outlineButton(
                              text: "Dismiss",
                              onPressed: () => _dismissAlert(id, index),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AppComponents.outlineButton(
                              text: "Investigate",
                              color: AppColors.danger,
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Feature coming soon')),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
