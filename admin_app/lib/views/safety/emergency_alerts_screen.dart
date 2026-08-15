import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class EmergencyAlertsScreen extends StatefulWidget {
  const EmergencyAlertsScreen({super.key});

  @override
  State<EmergencyAlertsScreen> createState() => _EmergencyAlertsScreenState();
}

class _EmergencyAlertsScreenState extends State<EmergencyAlertsScreen> {
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

  String _personName(Map<String, dynamic> alert) {
    final user = alert['user'] as Map<String, dynamic>?;
    if (user == null) return 'Unknown';
    return '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
  }

  String _personRole(Map<String, dynamic> alert) {
    final user = alert['user'] as Map<String, dynamic>?;
    if (user == null) return '';
    final role = user['role'] as String? ?? '';
    switch (role) {
      case 'RIDER':
        return 'Rider';
      case 'DRIVER':
        return 'Driver';
      case 'ADMIN':
        return 'Admin';
      default:
        return role;
    }
  }

  String _location(Map<String, dynamic> alert) {
    final trip = alert['trip'] as Map<String, dynamic>?;
    if (trip != null) {
      return '${trip['pickup'] ?? ''} → ${trip['destination'] ?? ''}'.trim();
    }
    return alert['message'] as String? ?? 'Location unknown';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Emergency Alerts")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Emergency Alerts")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('Failed to load alerts', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: () { setState(() { _loading = true; _error = null; }); _loadData(); }, child: const Text("Retry")),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Emergency Alerts")),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _alerts.isEmpty
            ? ListView(children: const [SizedBox(height: 100), Center(child: Text("No alerts", style: TextStyle(color: Colors.black54)))])
            : ListView(
                padding: const EdgeInsets.all(16),
                children: _alerts.map((alert) {
                  final resolved = alert['status'] == 'RESOLVED';
                  final createdAt = alert['createdAt'] != null
                      ? DateTime.tryParse(alert['createdAt'].toString()) ?? DateTime.now()
                      : DateTime.now();
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
                              Text("${_personName(alert)} (${_personRole(alert)})", style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(_location(alert), style: const TextStyle(fontSize: 12.5)),
                              const SizedBox(height: 2),
                              Text(formatFriendlyDate(createdAt), style: const TextStyle(fontSize: 11, color: Colors.black45)),
                            ],
                          ),
                        ),
                        if (resolved)
                          AppComponents.badge("Resolved", color: AppColors.success)
                        else
                          ElevatedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Dispatch help: Feature coming soon')),
                              );
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
                            child: const Text("Dispatch help"),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ),
    );
  }
}
