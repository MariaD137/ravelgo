import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

/// Live SOS emergency alerts (GET /api/emergency-alerts, filtered to type SOS).
class EmergencyAlertsScreen extends StatefulWidget {
  const EmergencyAlertsScreen({super.key});

  @override
  State<EmergencyAlertsScreen> createState() => _EmergencyAlertsScreenState();
}

class _EmergencyAlertsScreenState extends State<EmergencyAlertsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<EmergencyAlert> _alerts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await AdminApi.alerts();
      if (!mounted) return;
      setState(() {
        _alerts = all.where((a) => a.type == 'SOS').toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403 ? 'Sign in as an admin to view alerts.' : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(EmergencyAlert a, String status) async {
    setState(() => _busy = true);
    try {
      await AdminApi.setAlertStatus(a.id, status);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _color(String s) {
    switch (s) {
      case 'RESOLVED':
        return AppColors.success;
      case 'ACKNOWLEDGED':
        return AppColors.info;
      default:
        return AppColors.danger;
    }
  }

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Emergency Alerts")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null ? _err() : _list()),
    );
  }

  Widget _err() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _list() {
    if (_alerts.isEmpty) {
      return const Center(child: Text("No SOS alerts.", style: TextStyle(color: AppColors.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _alerts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final a = _alerts[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sos, color: AppColors.danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(a.userName.isEmpty ? 'User' : a.userName,
                            style: const TextStyle(fontWeight: FontWeight.w600))),
                    AppComponents.badge(_label(a.status), color: _color(a.status)),
                  ],
                ),
                if (a.message != null && a.message!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(a.message!, style: const TextStyle(fontSize: 13)),
                ],
                const SizedBox(height: 4),
                Text(formatFriendlyDate(a.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Row(
                  children: [
                    if (a.status == 'OPEN')
                      TextButton(onPressed: _busy ? null : () => _setStatus(a, 'ACKNOWLEDGED'), child: const Text('Acknowledge')),
                    if (a.status != 'RESOLVED')
                      TextButton(onPressed: _busy ? null : () => _setStatus(a, 'RESOLVED'), child: const Text('Resolve')),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
