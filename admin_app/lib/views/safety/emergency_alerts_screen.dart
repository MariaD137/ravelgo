import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/widgets/pagination_bar.dart';

import 'package:ravelgo_admin/utils/date_utils.dart';

/// Live SOS emergency alerts (GET /api/emergency-alerts?type=SOS, paged).
class EmergencyAlertsScreen extends StatefulWidget {
  const EmergencyAlertsScreen({super.key});

  @override
  State<EmergencyAlertsScreen> createState() => _EmergencyAlertsScreenState();
}

class _EmergencyAlertsScreenState extends State<EmergencyAlertsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  List<EmergencyAlert> _alerts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? page}) async {
    if (page != null) _page = page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Filtered server-side by type, so this pages through every SOS alert
      // rather than the SOS subset of one mixed page.
      final result = await AdminApi.alerts(type: 'SOS', page: _page);
      if (!mounted) return;
      if (result.isPastEnd) return await _load(page: result.totalPages);
      setState(() {
        _alerts = result.items;
        _total = result.total;
        _totalPages = result.totalPages;
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
    return Column(
      children: [
        Expanded(child: _listView()),
        PaginationBar(
          page: _page,
          totalPages: _totalPages,
          total: _total,
          itemLabel: 'alerts',
          busy: _loading,
          onPageChanged: (p) => _load(page: p),
        ),
      ],
    );
  }

  Widget _listView() {
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
