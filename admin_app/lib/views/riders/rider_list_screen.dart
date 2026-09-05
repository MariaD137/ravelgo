import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/riders/rider_detail_screen.dart';

class RiderListScreen extends StatefulWidget {
  const RiderListScreen({super.key});

  @override
  State<RiderListScreen> createState() => _RiderListScreenState();
}

class _RiderListScreenState extends State<RiderListScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<AdminRider> _riders = const [];

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
      final riders = await AdminApi.riders();
      if (!mounted) return;
      setState(() {
        _riders = riders;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'Sign in as an admin to view riders.'
            : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setSuspended(AdminRider r, bool suspended) async {
    setState(() => _busy = true);
    try {
      await AdminApi.setRiderSuspended(r.id, suspended);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(suspended ? 'Rider suspended' : 'Rider reinstated')));
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Riders")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null ? _errorView() : _list()),
    );
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
    if (_riders.isEmpty) {
      return const Center(child: Text("No riders yet.", style: TextStyle(color: AppColors.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _riders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = _riders[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => RiderDetailScreen(rider: r)));
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
                      Text(r.name.isEmpty ? r.email : r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(r.email, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                AppComponents.badge(r.suspended ? "Suspended" : "Active",
                    color: r.suspended ? AppColors.danger : AppColors.success),
                PopupMenuButton<bool>(
                  enabled: !_busy,
                  onSelected: (v) => _setSuspended(r, v),
                  itemBuilder: (_) => [
                    if (!r.suspended) const PopupMenuItem(value: true, child: Text('Suspend')),
                    if (r.suspended) const PopupMenuItem(value: false, child: Text('Reinstate')),
                  ],
                ),
              ],
            ),
            ),
          );
        },
      ),
    );
  }
}
