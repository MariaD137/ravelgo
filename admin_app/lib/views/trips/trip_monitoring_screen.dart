import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/widgets/admin_search_field.dart';
import 'package:ravelgo_admin/widgets/pagination_bar.dart';

import 'package:ravelgo_admin/utils/date_utils.dart';
import 'package:ravelgo_admin/views/trips/trip_admin_detail_screen.dart';

class TripMonitoringScreen extends StatefulWidget {
  final bool embedded;
  // Opens the list pre-filtered — e.g. the dashboard's "Active rides now" or
  // "Pending ride requests" tiles land here already narrowed to what that
  // tile counted. Empty/null means show every status.
  final Set<String>? initialStatusFilter;
  const TripMonitoringScreen({
    super.key,
    this.embedded = false,
    this.initialStatusFilter,
  });

  @override
  State<TripMonitoringScreen> createState() => _TripMonitoringScreenState();
}

class _TripMonitoringScreenState extends State<TripMonitoringScreen> {
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  List<AdminTrip> _trips = const [];
  Set<String> _statusFilter = {};
  String? _q;

  static const _statuses = [
    'REQUESTED',
    'MATCHED',
    'IN_PROGRESS',
    'COMPLETED',
    'CANCELLED',
    'DISPUTED',
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
      // Status chips and the search term are both applied server-side (GET
      // /api/trips?status=...&q=...), so a filter narrows the whole table
      // and pages within that subset.
      final result = await AdminApi.trips(statuses: _statusFilter, q: _q, page: _page);
      if (!mounted) return;
      if (result.isPastEnd) return await _load(page: result.totalPages);
      setState(() {
        _trips = result.items;
        _total = result.total;
        _totalPages = result.totalPages;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'Sign in as an admin to monitor trips.'
            : e.toString();
        _loading = false;
      });
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'IN_PROGRESS':
      case 'MATCHED':
        return AppColors.info;
      case 'COMPLETED':
        return AppColors.success;
      case 'DISPUTED':
        return AppColors.danger;
      default:
        return AppColors.textMuted;
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
    final Widget body = Column(
      children: [
        AdminSearchField(hintText: 'Search trip id, rider or driver…', onChanged: _onSearchChanged),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_error != null
                    ? _errorView()
                    : Column(
                        children: [
                          _filterBar(),
                          Expanded(child: _list()),
                        ],
                      )),
        ),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text("Trips")),
      body: body,
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
              selectedColor: _statusColor(s).withValues(alpha: 0.15),
              onSelected: (v) => _toggleStatus(s, v),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _errorView() => Center(
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
          itemLabel: 'trips',
          busy: _loading,
          onPageChanged: (p) => _load(page: p),
        ),
      ],
    );
  }

  Widget _listView() {
    final trips = _trips;
    if (trips.isEmpty) {
      final message = _q != null
          ? "No trips match \"$_q\"."
          : (_statusFilter.isEmpty ? "No trips yet." : "No trips match this filter.");
      return Center(child: Text(message, style: const TextStyle(color: AppColors.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: trips.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final t = trips[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TripAdminDetailScreen(trip: t)),
            ),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AppComponents.cardDecoration(),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${t.riderName.isEmpty ? 'Rider' : t.riderName}  →  ${t.driverName ?? 'Unassigned'}",
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${t.pickup} to ${t.destination}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatFriendlyDate(t.requestedAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AppComponents.badge(
                        _label(t.status),
                        color: _statusColor(t.status),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        Currency.format(t.fare, decimals: 0),
                        style: const TextStyle(fontWeight: FontWeight.w700),
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
