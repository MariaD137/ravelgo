import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/widgets/admin_search_field.dart';
import 'package:ravelgo_admin/widgets/pagination_bar.dart';
import 'package:ravelgo_admin/widgets/reject_reason_dialog.dart';

import 'package:ravelgo_admin/views/rentals/rental_listing_detail_screen.dart';

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
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  String? _q;
  List<RentalListing> _items = const [];

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
      final result = await AdminApi.rentals(page: _page, q: _q);
      if (!mounted) return;
      if (result.isPastEnd) return await _load(page: result.totalPages);
      setState(() {
        _items = result.items;
        _total = result.total;
        _totalPages = result.totalPages;
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
    String? rejectionReason;
    if (approve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Approve this listing?'),
          content: Text('${r.vehicle.isEmpty ? 'This vehicle' : r.vehicle} will become visible to riders for rental.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    } else {
      // Rejecting requires a reason — same as document/vehicle rejection —
      // so the driver knows what to fix before resubmitting.
      final reason = await showDialog<String>(
        context: context,
        builder: (context) => RejectReasonDialog(itemLabel: r.vehicle.isEmpty ? 'this listing' : r.vehicle),
      );
      if (reason == null || !mounted) return; // cancelled
      rejectionReason = reason;
    }

    setState(() => _busy = true);
    try {
      await AdminApi.setRentalStatus(r.id, status, rejectionReason: rejectionReason);
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

  void _onSearchChanged(String? q) {
    _q = q;
    _load(page: 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Luxury Rental Listings")),
      body: Column(
        children: [
          AdminSearchField(hintText: 'Search vehicle, plate or owner…', onChanged: _onSearchChanged),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null ? _err() : _list()),
          ),
        ],
      ),
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
          itemLabel: 'listings',
          busy: _loading,
          onPageChanged: (p) => _load(page: p),
        ),
      ],
    );
  }

  Widget _listView() {
    if (_items.isEmpty) {
      return Center(
        child: Text(
          _q == null ? "No rental listings." : "No listings match \"$_q\".",
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
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
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final changed = await Navigator.push<bool>(
                  context, MaterialPageRoute(builder: (_) => RentalListingDetailScreen(listing: r)));
              if (changed == true) _load();
            },
            child: Container(
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
                if (r.status == 'REJECTED' && (r.rejectionReason?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Reason: ${r.rejectionReason}',
                        style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                  ),
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
            ),
          );
        },
      ),
    );
  }
}
