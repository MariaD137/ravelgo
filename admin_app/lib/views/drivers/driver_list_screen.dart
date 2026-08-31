import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/drivers/driver_detail_screen.dart';

class DriverListScreen extends StatefulWidget {
  final bool embedded;
  const DriverListScreen({super.key, this.embedded = false});

  @override
  State<DriverListScreen> createState() => _DriverListScreenState();
}

class _DriverListScreenState extends State<DriverListScreen> {
  bool _loading = true;
  String? _error;
  List<AdminDriver> _drivers = const [];

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
      final drivers = await AdminApi.drivers();
      if (!mounted) return;
      setState(() {
        _drivers = drivers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'Sign in as an admin to view drivers.'
            : e.toString();
        _loading = false;
      });
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'ACTIVE':
        return AppColors.success;
      case 'PENDING_REVIEW':
        return AppColors.warning;
      default:
        return AppColors.danger;
    }
  }

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final Widget body = _loading
        ? const Center(child: CircularProgressIndicator())
        : (_error != null ? _errorView() : _list());
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Drivers")), body: body);
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );

  Widget _list() {
    if (_drivers.isEmpty) {
      return const Center(child: Text("No drivers yet.", style: TextStyle(color: AppColors.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _drivers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final d = _drivers[i];
          return InkWell(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => DriverDetailScreen(driverId: d.id)));
              _load();
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AppComponents.cardDecoration(),
              child: Row(
                children: [
                  const CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.surfaceElevated,
                      child: Icon(Icons.person, color: AppColors.textSecondary)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name.isEmpty ? d.email : d.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                            "${d.totalTrips} trips · ★ ${d.rating.toStringAsFixed(1)}${d.isOnline ? ' · online' : ''}",
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  AppComponents.badge(_label(d.status), color: _statusColor(d.status)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
