import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/widgets/admin_search_field.dart';
import 'package:ravelgo_admin/widgets/pagination_bar.dart';
import 'package:ravelgo_admin/widgets/reject_reason_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ravelgo_admin/utils/date_utils.dart';

/// Car Paddy verification requests (GET /api/car-paddy, admin). A request is
/// a vehicle license renewal — the plate number alone gives an admin nothing
/// to actually verify against, so this reads the driver-submitted renewal
/// date and lets the admin open the supporting document/receipt (a fresh
/// signed URL each time, same on-demand pattern as driver documents) before
/// deciding.
class CarPaddyRequestsScreen extends StatefulWidget {
  const CarPaddyRequestsScreen({super.key});

  @override
  State<CarPaddyRequestsScreen> createState() => _CarPaddyRequestsScreenState();
}

class _CarPaddyRequestsScreenState extends State<CarPaddyRequestsScreen> {
  bool _loading = true;
  bool _busy = false;
  // Tracks which single request's document is mid signed-URL-fetch, so only
  // that request's button shows a spinner rather than blocking the screen.
  String? _viewingDocId;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  String? _q;
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
      final result = await AdminApi.carPaddyRequests(page: _page, q: _q);
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

  void _onSearchChanged(String? q) {
    _q = q;
    _load(page: 1);
  }

  Future<void> _viewDocument(CarPaddyRequest r) async {
    if (_viewingDocId != null) return;
    setState(() => _viewingDocId = r.id);
    try {
      final url = await AdminApi.carPaddyDocumentUrl(r.id);
      final uri = Uri.tryParse(url);
      if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _snack('Could not open this document.');
      }
    } catch (e) {
      _snack(e is ApiException ? e.message : 'Could not open this document.');
    } finally {
      if (mounted) setState(() => _viewingDocId = null);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _review(CarPaddyRequest r, String status) async {
    String? rejectionReason;
    if (status == 'REJECTED') {
      final reason = await showDialog<String>(
        context: context,
        builder: (context) => RejectReasonDialog(itemLabel: r.plateNumber),
      );
      if (reason == null) return; // cancelled
      rejectionReason = reason;
    }
    setState(() => _busy = true);
    try {
      await AdminApi.reviewCarPaddy(r.id, status, rejectionReason: rejectionReason);
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
      body: Column(
        children: [
          AdminSearchField(hintText: 'Search plate or driver…', onChanged: _onSearchChanged),
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
          itemLabel: 'requests',
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
          _q == null ? "No Car Paddy requests." : "No requests match \"$_q\".",
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
                Text("${r.driverName.isEmpty ? 'Driver' : r.driverName} · Submitted ${formatFriendlyDate(r.submittedAt)}",
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Text(
                  r.renewalDate == null ? 'Renewal date: Not provided' : 'Renewal date: ${formatFriendlyDate(r.renewalDate!)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                if (r.status == 'REJECTED' && (r.rejectionReason?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Reason: ${r.rejectionReason}',
                        style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                  ),
                Row(
                  children: [
                    if (r.hasDocument)
                      TextButton.icon(
                        onPressed: _viewingDocId != null ? null : () => _viewDocument(r),
                        icon: _viewingDocId == r.id
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('View document'),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No supporting document uploaded',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
                      ),
                  ],
                ),
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
