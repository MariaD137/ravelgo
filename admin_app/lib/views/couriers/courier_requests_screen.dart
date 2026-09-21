import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/widgets/admin_search_field.dart';
import 'package:ravelgo_admin/widgets/pagination_bar.dart';

import 'package:ravelgo_admin/utils/date_utils.dart';
import 'package:ravelgo_admin/views/couriers/courier_request_detail_screen.dart';

/// Courier delivery requests (GET /api/courier-requests, admin).
class CourierRequestsScreen extends StatefulWidget {
  // Opens the list pre-filtered — e.g. the dashboard's "Active deliveries"
  // tile lands here already narrowed to what that tile counted. Empty/null
  // means show every status.
  final Set<String>? initialStatusFilter;
  const CourierRequestsScreen({super.key, this.initialStatusFilter});

  @override
  State<CourierRequestsScreen> createState() => _CourierRequestsScreenState();
}

class _CourierRequestsScreenState extends State<CourierRequestsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  List<CourierRequest> _items = const [];
  Set<String> _statusFilter = {};
  String? _q;

  static const _statuses = [
    'REQUESTED',
    'MATCHED',
    'PICKED_UP',
    'IN_TRANSIT',
    'DELIVERED',
    'CANCELLED',
  ];

  @override
  void initState() {
    super.initState();
    _statusFilter = {...?widget.initialStatusFilter};
    _load();
  }

  Future<void> _load({int? page}) async {
    if (page != null) _page = page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Status chips and search are applied server-side (GET
      // /api/courier-requests?status=...&q=...).
      final result = await AdminApi.courierRequests(statuses: _statusFilter, q: _q, page: _page);
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
            ? 'Sign in as an admin to view requests.'
            : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(CourierRequest c, String status) async {
    setState(() => _busy = true);
    try {
      await AdminApi.setCourierStatus(c.id, status);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _color(String s) {
    switch (s) {
      case 'DELIVERED':
        return AppColors.success;
      case 'CANCELLED':
        return AppColors.danger;
      case 'IN_TRANSIT':
      case 'PICKED_UP':
      case 'MATCHED':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  String _label(String s) =>
      s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  void _toggleStatus(String status, bool selected) {
    setState(() => selected ? _statusFilter.add(status) : _statusFilter.remove(status));
    _load(page: 1); // a changed filter always restarts from the first page
  }

  void _onSearchChanged(String? q) {
    _q = q;
    _load(page: 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Courier Requests")),
      body: Column(
        children: [
          AdminSearchField(hintText: 'Search sender, driver or recipient…', onChanged: _onSearchChanged),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null
                      ? _err()
                      : Column(
                          children: [
                            _filterBar(),
                            Expanded(child: _list()),
                          ],
                        )),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          for (final s in _statuses) ...[
            FilterChip(
              label: Text(_label(s), style: const TextStyle(fontSize: 12)),
              selected: _statusFilter.contains(s),
              selectedColor: _color(s).withValues(alpha: 0.15),
              onSelected: (v) => _toggleStatus(s, v),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _err() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.danger),
          ),
          TextButton(onPressed: _load, child: const Text('Try again')),
        ],
      ),
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
          itemLabel: 'requests',
          busy: _loading,
          onPageChanged: (p) => _load(page: p),
        ),
      ],
    );
  }

  Widget _listView() {
    final items = _items;
    if (items.isEmpty) {
      final message = _q != null
          ? "No requests match \"$_q\"."
          : (_statusFilter.isEmpty ? "No courier requests." : "No requests match this filter.");
      return Center(child: Text(message, style: const TextStyle(color: AppColors.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final c = items[i];
          final done = c.status == 'DELIVERED' || c.status == 'CANCELLED';
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => CourierRequestDetailScreen(request: c),
                ),
              );
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
                        child: Text(
                          "${c.pickupAddress} → ${c.dropoffAddress}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      AppComponents.badge(
                        _label(c.status),
                        color: _color(c.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${c.packageDescription} · to ${c.recipientName}",
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    "From ${c.senderName.isEmpty ? 'Sender' : c.senderName}"
                    "${c.driverName != null ? ' · Driver: ${c.driverName}' : ''} · ${formatFriendlyDate(c.requestedAt)}",
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (!done)
                    Row(
                      children: [
                        if (c.status != 'IN_TRANSIT')
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _setStatus(c, 'IN_TRANSIT'),
                            child: const Text('In transit'),
                          ),
                        // No "Delivered" quick action here — the backend now
                        // requires a delivery photo and the recipient's
                        // signature to mark a request DELIVERED, which only
                        // the driver app captures. Admin can still cancel.
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _setStatus(c, 'CANCELLED'),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: AppColors.danger),
                          ),
                        ),
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
