import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/widgets/admin_search_field.dart';
import 'package:ravelgo_admin/widgets/pagination_bar.dart';

import 'package:ravelgo_admin/views/drivers/driver_detail_screen.dart';

class DriverListScreen extends StatefulWidget {
  final bool embedded;
  // Opens the list pre-filtered — e.g. the dashboard's "Pending approvals" or
  // "Online drivers" tiles land here already narrowed to what that tile
  // counted, instead of dumping the admin on the full unfiltered list.
  final String? initialStatusFilter; // PENDING_REVIEW | ACTIVE | SUSPENDED
  final bool initialOnlineOnly;
  const DriverListScreen({
    super.key,
    this.embedded = false,
    this.initialStatusFilter,
    this.initialOnlineOnly = false,
  });

  @override
  State<DriverListScreen> createState() => _DriverListScreenState();
}

class _DriverListScreenState extends State<DriverListScreen> {
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  List<AdminDriver> _drivers = const [];
  String? _statusFilter;
  bool _onlineOnly = false;
  String? _q;

  static const _statuses = ['PENDING_REVIEW', 'ACTIVE', 'SUSPENDED'];

  @override
  void initState() {
    super.initState();
    _statusFilter = widget.initialStatusFilter;
    _onlineOnly = widget.initialOnlineOnly;
    _load();
  }

  Future<void> _load({int? page}) async {
    if (page != null) _page = page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // The status chip and search term are both applied server-side so this
      // list is complete for that filter, not just the first page of all
      // drivers.
      final result = await AdminApi.drivers(status: _statusFilter, q: _q, page: _page);
      if (!mounted) return;
      if (result.isPastEnd) return await _load(page: result.totalPages);
      setState(() {
        _drivers = result.items;
        _total = result.total;
        _totalPages = result.totalPages;
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

  String _label(String s) =>
      s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  List<AdminDriver> get _filtered => _drivers.where((d) => !_onlineOnly || d.isOnline).toList();

  void _setStatusFilter(String? status) {
    if (status == _statusFilter) return;
    setState(() => _statusFilter = status);
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
        AdminSearchField(hintText: 'Search name, email, phone or plate…', onChanged: _onSearchChanged),
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
      appBar: AppBar(title: const Text("Drivers")),
      body: body,
    );
  }

  Widget _filterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          FilterChip(
            label: const Text('All', style: TextStyle(fontSize: 12)),
            selected: _statusFilter == null,
            onSelected: (_) => _setStatusFilter(null),
          ),
          const SizedBox(width: 8),
          for (final s in _statuses) ...[
            FilterChip(
              label: Text(_label(s), style: const TextStyle(fontSize: 12)),
              selected: _statusFilter == s,
              selectedColor: _statusColor(s).withValues(alpha: 0.15),
              onSelected: (v) => _setStatusFilter(v ? s : null),
            ),
            const SizedBox(width: 8),
          ],
          FilterChip(
            label: const Text('Online only', style: TextStyle(fontSize: 12)),
            selected: _onlineOnly,
            selectedColor: AppColors.success.withValues(alpha: 0.15),
            onSelected: (v) => setState(() => _onlineOnly = v),
          ),
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
          itemLabel: 'drivers',
          busy: _loading,
          onPageChanged: (p) => _load(page: p),
        ),
      ],
    );
  }

  Widget _listView() {
    final drivers = _filtered;
    if (drivers.isEmpty) {
      final message = _drivers.isEmpty
          ? (_q == null ? "No drivers yet." : "No drivers match \"$_q\".")
          : "No drivers match this filter.";
      return Center(
        child: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: drivers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final d = drivers[i];
          return InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DriverDetailScreen(driverId: d.id),
                ),
              );
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
                    child: Icon(Icons.person, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name.isEmpty ? d.email : d.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${d.totalTrips} trips · ★ ${d.rating.toStringAsFixed(1)}${d.isOnline ? ' · online' : ''}",
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppComponents.badge(
                    _label(d.status),
                    color: _statusColor(d.status),
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
