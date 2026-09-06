import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

/// Courier delivery requests (GET /api/courier-requests, admin).
class CourierRequestsScreen extends StatefulWidget {
  const CourierRequestsScreen({super.key});

  @override
  State<CourierRequestsScreen> createState() => _CourierRequestsScreenState();
}

class _CourierRequestsScreenState extends State<CourierRequestsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<CourierRequest> _items = const [];

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
      final items = await AdminApi.courierRequests();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _setStatus(CourierRequest c, String status) async {
    setState(() => _busy = true);
    try {
      await AdminApi.setCourierStatus(c.id, status);
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

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Courier Requests")),
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
      return const Center(child: Text("No courier requests.", style: TextStyle(color: AppColors.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final c = _items[i];
          final done = c.status == 'DELIVERED' || c.status == 'CANCELLED';
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text("${c.pickupAddress} → ${c.dropoffAddress}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                    AppComponents.badge(_label(c.status), color: _color(c.status)),
                  ],
                ),
                const SizedBox(height: 4),
                Text("${c.packageDescription} · to ${c.recipientName}",
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Text("From ${c.senderName.isEmpty ? 'Sender' : c.senderName}"
                    "${c.driverName != null ? ' · Driver: ${c.driverName}' : ''} · ${formatFriendlyDate(c.requestedAt)}",
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                if (!done)
                  Row(
                    children: [
                      if (c.status != 'IN_TRANSIT')
                        TextButton(onPressed: _busy ? null : () => _setStatus(c, 'IN_TRANSIT'), child: const Text('In transit')),
                      // No "Delivered" quick action here — the backend now
                      // requires a delivery photo and the recipient's
                      // signature to mark a request DELIVERED, which only
                      // the driver app captures. Admin can still cancel.
                      TextButton(
                          onPressed: _busy ? null : () => _setStatus(c, 'CANCELLED'),
                          child: const Text('Cancel', style: TextStyle(color: AppColors.danger))),
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
