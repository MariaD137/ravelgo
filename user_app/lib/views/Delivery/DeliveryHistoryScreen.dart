import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/courier_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/Delivery/DeliveryTrackingScreen.dart';

/// All delivery requests this customer has sent. Backed by the real
/// GET /api/courier-requests/sent — no fabricated history.
class DeliveryHistoryScreen extends StatefulWidget {
  const DeliveryHistoryScreen({super.key});

  @override
  State<DeliveryHistoryScreen> createState() => _DeliveryHistoryScreenState();
}

class _DeliveryHistoryScreenState extends State<DeliveryHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<CourierRequest> _requests = const [];

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
      final requests = await CourierApi.sent();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'DELIVERED':
        return AppColors.success;
      case 'CANCELLED':
        return AppColors.error;
      case 'IN_TRANSIT':
      case 'PICKED_UP':
      case 'MATCHED':
        return AppColors.primaryDark;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery history')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_requests.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('You haven\'t sent any packages yet.', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _requests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = _requests[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeliveryTrackingScreen(deliveryId: r.id))),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r.pickupAddress} → ${r.dropoffAddress}', style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('${r.requestedAt.toLocal()}'.split('.').first, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(Currency.format(r.finalFare ?? r.estimatedFare, decimals: 0), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(r.status, style: TextStyle(color: _statusColor(r.status), fontSize: 11, fontWeight: FontWeight.w600)),
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
