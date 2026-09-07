import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// Luxury rental listings awaiting review (GET /api/rentals, admin sees all).
class RentalListingsScreen extends StatefulWidget {
  const RentalListingsScreen({super.key});

  @override
  State<RentalListingsScreen> createState() => _RentalListingsScreenState();
}

class _RentalListingsScreenState extends State<RentalListingsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<RentalListing> _items = const [];

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
      final items = await AdminApi.rentals();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403 ? 'Sign in as an admin to view listings.' : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(RentalListing r, String status) async {
    final approve = status == 'APPROVED';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Approve this listing?' : 'Reject this listing?'),
        content: Text(approve
            ? '${r.vehicle.isEmpty ? 'This vehicle' : r.vehicle} will become visible to riders for rental.'
            : '${r.vehicle.isEmpty ? 'This vehicle' : r.vehicle} will be hidden from riders.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: approve ? null : ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await AdminApi.setRentalStatus(r.id, status);
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
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Luxury Rental Listings")),
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
    if (_items.isEmpty) {
      return const Center(child: Text("No rental listings.", style: TextStyle(color: AppColors.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = _items[i];
          final decided = r.status == 'APPROVED' || r.status == 'REJECTED';
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(r.vehicle.isEmpty ? 'Vehicle' : r.vehicle,
                            style: const TextStyle(fontWeight: FontWeight.w600))),
                    AppComponents.badge(_label(r.status), color: _color(r.status)),
                  ],
                ),
                const SizedBox(height: 4),
                Text("${Currency.format(r.dailyRate, decimals: 0)}/day · ${r.location}"
                    "${r.driverName.isNotEmpty ? ' · ${r.driverName}' : ''}",
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                if (!decided)
                  Row(
                    children: [
                      TextButton(onPressed: _busy ? null : () => _setStatus(r, 'APPROVED'), child: const Text('Approve')),
                      TextButton(
                          onPressed: _busy ? null : () => _setStatus(r, 'REJECTED'),
                          child: const Text('Reject', style: TextStyle(color: AppColors.danger))),
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
