import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/courier_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Live-ish status for a single delivery request. There's no realtime feed
/// for courier requests (unlike Trip's WebSocket), so this polls the real
/// status endpoint — never fabricated progress.
class DeliveryTrackingScreen extends StatefulWidget {
  final String deliveryId;
  const DeliveryTrackingScreen({super.key, required this.deliveryId});

  @override
  State<DeliveryTrackingScreen> createState() => _DeliveryTrackingScreenState();
}

class _DeliveryTrackingScreenState extends State<DeliveryTrackingScreen> {
  Timer? _poll;
  bool _loading = true;
  String? _error;
  CourierRequest? _request;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final request = await CourierApi.status(widget.deliveryId);
      if (!mounted) return;
      setState(() {
        _request = request;
        _error = null;
        _loading = false;
      });
      if (request.status == 'DELIVERED' || request.status == 'CANCELLED') {
        _poll?.cancel();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'REQUESTED':
        return 'Looking for a courier…';
      case 'MATCHED':
        return 'Courier assigned';
      case 'IN_TRANSIT':
        return 'On the way';
      case 'DELIVERED':
        return 'Delivered';
      case 'CANCELLED':
        return 'Cancelled';
      default:
        return s;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'DELIVERED':
        return AppColors.success;
      case 'CANCELLED':
        return AppColors.error;
      case 'IN_TRANSIT':
      case 'MATCHED':
        return AppColors.primaryDark;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery status')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && _request == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _request == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              TextButton(onPressed: () => _load(), child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final r = _request!;
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _statusColor(r.status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Icon(
                  r.status == 'DELIVERED'
                      ? Icons.check_circle
                      : r.status == 'CANCELLED'
                          ? Icons.cancel
                          : Icons.local_shipping,
                  color: _statusColor(r.status),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_statusLabel(r.status), style: TextStyle(fontWeight: FontWeight.w700, color: _statusColor(r.status))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _row('From', r.pickupAddress),
          _row('To', r.dropoffAddress),
          _row('Recipient', '${r.recipientName} · ${r.recipientPhone}'),
          _row('Package', r.packageDescription.isEmpty ? r.packageSize : r.packageDescription),
          const Divider(height: 24),
          _row('Price', Currency.format(r.finalFare ?? r.estimatedFare, decimals: 0), bold: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: 15)),
          ],
        ),
      );
}
