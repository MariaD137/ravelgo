import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/widgets/pagination_bar.dart';

import 'package:ravelgo_admin/utils/date_utils.dart';

/// Car Paddy verification requests (GET /api/car-paddy, admin).
class CarPaddyRequestsScreen extends StatefulWidget {
  const CarPaddyRequestsScreen({super.key});

  @override
  State<CarPaddyRequestsScreen> createState() => _CarPaddyRequestsScreenState();
}

class _CarPaddyRequestsScreenState extends State<CarPaddyRequestsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  List<CarPaddyRequest> _items = const [];

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
      final result = await AdminApi.carPaddyRequests(page: _page);
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
        _error = e is ApiException && e.statusCode == 403 ? 'Sign in as an admin to view requests.' : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _review(CarPaddyRequest r, String status) async {
    setState(() => _busy = true);
    try {
      await AdminApi.reviewCarPaddy(r.id, status);
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
      case 'IN_REVIEW':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Car Paddy Requests")),
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
          itemLabel: 'requests',
          busy: _loading,
          onPageChanged: (p) => _load(page: p),
        ),
      ],
    );
  }

  Widget _listView() {
    if (_items.isEmpty) {
      return const Center(child: Text("No Car Paddy requests.", style: TextStyle(color: AppColors.textSecondary)));
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
                    Expanded(child: Text(r.plateNumber, style: const TextStyle(fontWeight: FontWeight.w600))),
                    AppComponents.badge(_label(r.status), color: _color(r.status)),
                  ],
                ),
                const SizedBox(height: 4),
                Text("${r.driverName.isEmpty ? 'Driver' : r.driverName} · ${formatFriendlyDate(r.submittedAt)}",
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                if (!decided)
                  Row(
                    children: [
                      TextButton(onPressed: _busy ? null : () => _review(r, 'APPROVED'), child: const Text('Approve')),
                      TextButton(
                          onPressed: _busy ? null : () => _review(r, 'REJECTED'),
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
