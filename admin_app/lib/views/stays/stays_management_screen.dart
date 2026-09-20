import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/widgets/pagination_bar.dart';

import 'package:ravelgo_admin/views/stays/stay_detail_screen.dart';

/// Short Stays admin management (GET/PATCH /api/stays — admin sees every
/// listing, including pending/rejected, with host info and booking counts).
class StaysManagementScreen extends StatefulWidget {
  const StaysManagementScreen({super.key});

  @override
  State<StaysManagementScreen> createState() => _StaysManagementScreenState();
}

class _StaysManagementScreenState extends State<StaysManagementScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  List<StayListing> _items = const [];

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
      final result = await AdminApi.stays(page: _page);
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
        _error = e is ApiException && e.statusCode == 403
            ? 'Sign in as an admin to manage short stays.'
            : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _decide(StayListing listing, String status) async {
    final approve = status == 'APPROVED';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Approve this listing?' : 'Reject this listing?'),
        content: Text(approve
            ? '"${listing.title}" will become visible to guests for booking.'
            : '"${listing.title}" will be hidden from guests.'),
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
      await AdminApi.setStayStatus(listing.id, status);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(approve ? 'Listing approved' : 'Listing rejected')));
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
      appBar: AppBar(title: const Text("Short Stays")),
      body: _loading ? const Center(child: CircularProgressIndicator()) : (_error != null ? _err() : _list()),
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
      return const Center(child: Text("No short-stay listings yet.", style: TextStyle(color: AppColors.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final s = _items[i];
          final pending = s.status == 'PENDING_APPROVAL';
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => StayDetailScreen(listing: s)));
              _load();
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
                          child: Text(s.title.isEmpty ? 'Listing' : s.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600))),
                      AppComponents.badge(_label(s.status), color: _color(s.status)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(s.address, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(
                    "${Currency.format(s.pricePerNight, decimals: 0)}/night · Sleeps ${s.maxGuests}"
                    "${s.host != null && s.host!.name.isNotEmpty ? ' · ${s.host!.name}' : ''}"
                    "${s.bookingCount != null ? ' · ${s.bookingCount} booking${s.bookingCount == 1 ? '' : 's'}' : ''}",
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (pending)
                    Row(
                      children: [
                        TextButton(
                            onPressed: _busy ? null : () => _decide(s, 'APPROVED'), child: const Text('Approve')),
                        TextButton(
                            onPressed: _busy ? null : () => _decide(s, 'REJECTED'),
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
