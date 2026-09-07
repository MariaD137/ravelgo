import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user_app/components/SafeGoogleMap.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/courier_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

// Statuses where a courier is actually assigned and could be reporting a
// location — matches the backend's own ACTIVE_COURIER_STATUSES
// (admin.routes.ts), so "is a courier expected" means the same thing here as
// it does on the admin Live Map.
const _activeCourierStatuses = {'MATCHED', 'PICKED_UP', 'IN_TRANSIT'};

/// Live-ish status for a single delivery request. There's no realtime feed
/// for courier requests (unlike Trip's WebSocket), so this polls the real
/// status endpoint — never fabricated progress. The same poll now also
/// carries the courier's live location (see CourierRequest.courierLat/Lng),
/// reusing the exact GPS feed behind the admin Live Map's Packages view —
/// never a second, independent tracking system.
class DeliveryTrackingScreen extends StatefulWidget {
  final String deliveryId;
  const DeliveryTrackingScreen({super.key, required this.deliveryId});

  @override
  State<DeliveryTrackingScreen> createState() => _DeliveryTrackingScreenState();
}

class _DeliveryTrackingScreenState extends State<DeliveryTrackingScreen> {
  // The real progression a delivery moves through. CANCELLED is a separate,
  // terminal branch off this line rather than a step within it.
  static const _steps = ['REQUESTED', 'MATCHED', 'PICKED_UP', 'IN_TRANSIT', 'DELIVERED'];
  static const _stepLabels = {
    'REQUESTED': 'Requested',
    'MATCHED': 'Courier assigned',
    'PICKED_UP': 'Picked up',
    'IN_TRANSIT': 'In transit',
    'DELIVERED': 'Delivered',
  };

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
          if (r.status == 'CANCELLED') _cancelledBanner() else _timeline(r.status),
          const SizedBox(height: 20),
          if (_hasAnyCoordinate(r)) ...[
            _map(r),
            const SizedBox(height: 12),
            _locationFreshnessLabel(r),
            const SizedBox(height: 20),
          ],
          _row('From', r.pickupAddress),
          _row('To', r.dropoffAddress),
          _row('Recipient', '${r.recipientName} · ${r.recipientPhone}'),
          _row('Package', r.packageDescription.isEmpty ? r.packageSize : r.packageDescription),
          const Divider(height: 24),
          _row('Price', Currency.format(r.finalFare ?? r.estimatedFare, decimals: 0), bold: true),
          if (r.status == 'DELIVERED' && (r.deliveryPhotoUrl != null || r.recipientSignatureUrl != null)) ...[
            const Divider(height: 24),
            const Text('Proof of delivery', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            if (r.deliveryPhotoUrl != null) _proofImage('Delivery photo', r.deliveryPhotoUrl!),
            if (r.deliveryPhotoUrl != null && r.recipientSignatureUrl != null) const SizedBox(height: 12),
            if (r.recipientSignatureUrl != null) _proofImage('Recipient signature', r.recipientSignatureUrl!, background: Colors.white),
          ],
        ],
      ),
    );
  }

  bool _hasAnyCoordinate(CourierRequest r) =>
      (r.pickupLat != null && r.pickupLng != null) ||
      (r.dropoffLat != null && r.dropoffLng != null) ||
      (r.courierLat != null && r.courierLng != null);

  Widget _map(CourierRequest r) {
    final markers = <Marker>{};
    if (r.pickupLat != null && r.pickupLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(r.pickupLat!, r.pickupLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ));
    }
    if (r.dropoffLat != null && r.dropoffLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('dropoff'),
        position: LatLng(r.dropoffLat!, r.dropoffLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Drop-off'),
      ));
    }
    if (r.courierLat != null && r.courierLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('courier'),
        position: LatLng(r.courierLat!, r.courierLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Courier'),
      ));
    }
    final center = markers.first.position;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 220,
        child: SafeGoogleMap(
          initialCameraPosition: CameraPosition(target: center, zoom: 13),
          markers: markers,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
        ),
      ),
    );
  }

  /// LIVE / STALE / no-report-yet / not-applicable — the same three-state
  /// freshness model the admin Live Map uses (backend/src/routes/admin.
  /// routes.ts's locationFreshness), so "live" never means something
  /// different here than it does for ops. Never shows a stale position as if
  /// it were current.
  Widget _locationFreshnessLabel(CourierRequest r) {
    String text;
    IconData icon;
    Color color;
    if (r.courierPresence == 'LIVE') {
      final seconds = r.courierLocationUpdatedAt == null
          ? 0
          : DateTime.now().difference(r.courierLocationUpdatedAt!).inSeconds.clamp(0, 999);
      text = 'Courier location updated ${seconds}s ago';
      icon = Icons.circle;
      color = AppColors.success;
    } else if (r.courierPresence == 'STALE') {
      final minutes = r.courierLocationUpdatedAt == null
          ? 0
          : DateTime.now().difference(r.courierLocationUpdatedAt!).inMinutes;
      text = "Courier location hasn't updated in ${minutes}m";
      icon = Icons.warning_amber_rounded;
      color = AppColors.textMuted;
    } else if (_activeCourierStatuses.contains(r.status)) {
      text = 'Courier location is temporarily unavailable';
      icon = Icons.location_off_outlined;
      color = AppColors.textMuted;
    } else {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12.5, color: color)),
      ],
    );
  }

  Widget _cancelledBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
      child: const Row(
        children: [
          Icon(Icons.cancel, color: AppColors.error),
          SizedBox(width: 12),
          Expanded(child: Text('Cancelled', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.error))),
        ],
      ),
    );
  }

  /// Vertical step timeline: filled + checked for completed steps, filled for
  /// the current one, hollow for steps not reached yet.
  Widget _timeline(String status) {
    final currentIndex = _steps.indexOf(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _steps.length; i++)
          _timelineRow(
            label: _stepLabels[_steps[i]]!,
            isDone: currentIndex >= 0 && i < currentIndex,
            isCurrent: i == currentIndex,
            isLast: i == _steps.length - 1,
          ),
      ],
    );
  }

  Widget _timelineRow({required String label, required bool isDone, required bool isCurrent, required bool isLast}) {
    final reached = isDone || isCurrent;
    final color = reached ? AppColors.primaryDark : AppColors.border;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone ? AppColors.primaryDark : Colors.transparent,
                  border: Border.all(color: color, width: 2),
                ),
                child: isDone
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : (isCurrent ? Center(child: Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryDark))) : null),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: reached && !isCurrent ? AppColors.primaryDark : AppColors.border)),
            ],
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                color: reached ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _proofImage(String label, String url, {Color? background}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: background ?? AppColors.surfaceElevated,
            child: Image.network(
              url,
              height: 180,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 180,
                child: Center(child: Text('Could not load image', style: TextStyle(color: AppColors.textMuted))),
              ),
            ),
          ),
        ),
      ],
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
