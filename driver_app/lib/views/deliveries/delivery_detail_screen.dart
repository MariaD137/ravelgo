import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ravelgo_driver_app/config/currency.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/deliveries/delivery_proof_screen.dart';
import 'package:ravelgo_driver_app/widgets/app_page_route.dart';
import 'package:ravelgo_driver_app/widgets/empty_state.dart';
import 'package:ravelgo_driver_app/widgets/shimmer.dart';

/// Full detail of one package delivery: Package / Pickup / Drop-off /
/// Assignment / Earnings, a map of the real pickup/dropoff/courier
/// coordinates (never fabricated), and the same accept/advance/proof-of-
/// delivery actions the Deliveries list already offers — every action here
/// calls the real backend endpoint, never just flips local state. Reachable
/// either from the Available tab (before accepting) or from Assigned/Active/
/// Completed (already this driver's job) — the backend enforces which one
/// applies, not this screen.
class DeliveryDetailScreen extends StatefulWidget {
  final String deliveryId;
  final CourierRequest? initial;

  const DeliveryDetailScreen({super.key, required this.deliveryId, this.initial});

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  static const _steps = ['REQUESTED', 'MATCHED', 'PICKED_UP', 'IN_TRANSIT', 'DELIVERED'];
  static const _stepLabels = {
    'REQUESTED': 'Requested',
    'MATCHED': 'Accepted',
    'PICKED_UP': 'Picked up',
    'IN_TRANSIT': 'In transit',
    'DELIVERED': 'Delivered',
  };
  static const _activeStatuses = {'MATCHED', 'PICKED_UP', 'IN_TRANSIT'};

  CourierRequest? _request;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  // True once the backend has told us this job is gone (already taken by
  // another driver, or otherwise no longer reachable) — surfaced distinctly
  // from a generic error so the driver understands why, not just "failed".
  bool _noLongerAvailable = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _request = widget.initial;
    _loading = widget.initial == null;
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = _request == null);
    try {
      final r = await DriverApi.deliveryDetail(widget.deliveryId);
      if (!mounted) return;
      setState(() {
        _request = r;
        _error = null;
        _noLongerAvailable = false;
        _loading = false;
      });
      _schedulePolling(r.status);
    } catch (e) {
      if (!mounted) return;
      final isGone = e is ApiException && (e.statusCode == 404 || e.statusCode == 403);
      setState(() {
        if (!silent || _request == null) {
          _noLongerAvailable = isGone && _request?.driverId == null;
          _error = e is ApiException ? e.message : 'Could not load this delivery — check your connection.';
        }
        _loading = false;
      });
    }
  }

  /// Only worth polling while the job could still change under us — an
  /// unassigned request another driver might take, or one already assigned
  /// and moving through pickup/transit (so the live courier pin stays fresh).
  /// A finished (DELIVERED/CANCELLED) request never changes again.
  void _schedulePolling(String status) {
    _poll?.cancel();
    if (status == 'DELIVERED' || status == 'CANCELLED') return;
    _poll = Timer(const Duration(seconds: 10), () => _load(silent: true));
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final updated = await DriverApi.acceptDelivery(widget.deliveryId);
      if (!mounted) return;
      setState(() {
        _request = updated;
        _noLongerAvailable = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery accepted.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      final isConflict = e is ApiException && e.statusCode == 409;
      setState(() {
        _noLongerAvailable = isConflict;
        _error = isConflict
            ? 'This delivery was just accepted by another driver.'
            : (e is ApiException ? e.message : e.toString());
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advance(String nextStatus) async {
    setState(() => _busy = true);
    try {
      final updated = await DriverApi.updateDeliveryStatus(widget.deliveryId, nextStatus);
      if (!mounted) return;
      setState(() => _request = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nextStatus == 'PICKED_UP' ? 'Marked picked up.' : 'On the way.')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Completing a delivery requires proof (photo + recipient signature) — the
  /// backend rejects DELIVERED without both — so this opens the same capture
  /// screen the Deliveries list uses, rather than a second implementation.
  Future<void> _completeDelivery() async {
    final current = _request;
    if (current == null) return;
    final updated = await Navigator.of(context).push<CourierRequest>(
      AppPageRoute(builder: (_) => DeliveryProofScreen(request: current)),
    );
    if (updated != null && mounted) {
      setState(() => _request = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked delivered.')));
      await _load();
    }
  }

  Future<void> _navigateTo(double? lat, double? lng, String address) async {
    final uri = (lat != null && lng != null)
        ? Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving')
        : Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address)}');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Maps.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery details')),
      body: _body(),
    );
  }

  Widget _body() {
    final r = _request;
    return AsyncBody(
      stateKey: (_loading && r == null) ? "loading" : (r == null ? "error" : "data:${r.id}:${r.status}"),
      child: (_loading && r == null)
          ? const ShimmerDetail()
          : r == null
              ? EmptyState(
                  icon: Icons.local_shipping_outlined,
                  title: _noLongerAvailable ? "No longer available" : "Couldn't load this delivery",
                  subtitle: _noLongerAvailable
                      ? 'This delivery is no longer available.'
                      : (_error ?? 'Could not load this delivery.'),
                  onRetry: () => _load(),
                )
              : _detail(r),
    );
  }

  Widget _detail(CourierRequest r) {
    final canPreviewOnly = r.status == 'REQUESTED' && r.driverId == null;
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ),
            const SizedBox(height: 16),
          ],
          if (r.status == 'CANCELLED') _cancelledBanner() else if (!canPreviewOnly) _timeline(r.status),
          if (!canPreviewOnly) const SizedBox(height: 20),
          if (_hasAnyCoordinate(r)) ...[
            _map(r),
            const SizedBox(height: 12),
            if (_activeStatuses.contains(r.status)) _locationFreshnessLabel(r),
            const SizedBox(height: 12),
          ],
          _sectionCard('Package', [
            _row('Description', r.packageDescription),
            _row('Size', r.packageSize),
          ]),
          const SizedBox(height: 12),
          _sectionCard('Pickup', [
            _row('Address', r.pickupAddress),
            if (r.distanceKm != null) _row('Distance to drop-off', '${r.distanceKm!.toStringAsFixed(1)} km'),
          ], action: r.status != 'DELIVERED' && r.status != 'CANCELLED'
              ? _navButton('Navigate to pickup', () => _navigateTo(r.pickupLat, r.pickupLng, r.pickupAddress))
              : null),
          const SizedBox(height: 12),
          _sectionCard('Drop-off', [
            _row('Address', r.dropoffAddress),
            _row('Recipient', '${r.recipientName} · ${r.recipientPhone}'),
          ], action: (r.status == 'PICKED_UP' || r.status == 'IN_TRANSIT')
              ? _navButton('Navigate to drop-off', () => _navigateTo(r.dropoffLat, r.dropoffLng, r.dropoffAddress))
              : null),
          const SizedBox(height: 12),
          _sectionCard('Assignment', [
            _row('Status', _label(r.status)),
            _row('Requested', _formatDateTime(r.requestedAt)),
            if (r.senderName != null) _row('Customer', r.senderName!),
          ]),
          const SizedBox(height: 12),
          _sectionCard('Earnings', _earningsRows(r)),
          if (r.status == 'DELIVERED' && (r.deliveryPhotoUrl != null || r.recipientSignatureUrl != null)) ...[
            const SizedBox(height: 12),
            _sectionCard('Proof of delivery', [
              if (r.deliveryPhotoUrl != null) _proofImage('Delivery photo', r.deliveryPhotoUrl!),
              if (r.deliveryPhotoUrl != null && r.recipientSignatureUrl != null) const SizedBox(height: 12),
              if (r.recipientSignatureUrl != null) _proofImage('Recipient signature', r.recipientSignatureUrl!, background: Colors.white),
            ]),
          ],
          const SizedBox(height: 24),
          _actionButton(r),
        ],
      ),
    );
  }

  Widget _actionButton(CourierRequest r) {
    Widget? button;
    if (r.status == 'REQUESTED' && r.driverId == null) {
      button = AppComponents.primaryButton(text: _busy ? 'Accepting…' : 'Accept delivery', onPressed: _busy ? null : _accept);
    } else if (r.status == 'MATCHED') {
      button = AppComponents.primaryButton(text: _busy ? 'Updating…' : 'Mark picked up', onPressed: _busy ? null : () => _advance('PICKED_UP'));
    } else if (r.status == 'PICKED_UP') {
      button = AppComponents.primaryButton(text: _busy ? 'Updating…' : 'Start delivery', onPressed: _busy ? null : () => _advance('IN_TRANSIT'));
    } else if (r.status == 'IN_TRANSIT') {
      button = AppComponents.primaryButton(text: 'Mark delivered', onPressed: _busy ? null : _completeDelivery);
    }
    return button ?? const SizedBox.shrink();
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
        markerId: const MarkerId('me'),
        position: LatLng(r.courierLat!, r.courierLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'You'),
      ));
    }
    final center = markers.first.position;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 200,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: center, zoom: 13),
          markers: markers,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
        ),
      ),
    );
  }

  /// Same LIVE/STALE/unavailable model the customer app's tracking screen and
  /// the admin Live Map use — never shows a stale position as current, and
  /// never fabricates one when this driver hasn't reported a fix yet.
  Widget _locationFreshnessLabel(CourierRequest r) {
    String text;
    IconData icon;
    Color color;
    if (r.courierPresence == 'LIVE') {
      final seconds = r.courierLocationUpdatedAt == null
          ? 0
          : DateTime.now().difference(r.courierLocationUpdatedAt!).inSeconds.clamp(0, 999);
      text = 'Your location updated ${seconds}s ago';
      icon = Icons.circle;
      color = AppColors.success;
    } else if (r.courierPresence == 'STALE') {
      text = "Your location hasn't updated recently — check GPS.";
      icon = Icons.warning_amber_rounded;
      color = AppColors.warning;
    } else {
      text = 'Your location is temporarily unavailable — check GPS/location permission.';
      icon = Icons.location_off_outlined;
      color = AppColors.textMuted;
    }
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: color))),
      ],
    );
  }

  Widget _cancelledBanner() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
        child: const Row(
          children: [
            Icon(Icons.cancel, color: AppColors.danger),
            SizedBox(width: 12),
            Expanded(child: Text('Cancelled', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger))),
          ],
        ),
      );

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

  Widget _sectionCard(String title, List<Widget> rows, {Widget? action}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: AppComponents.cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            ...rows,
            if (action != null) ...[const SizedBox(height: 10), action],
          ],
        ),
      );

  Widget _navButton(String label, VoidCallback onPressed) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.directions_outlined, size: 18),
        label: Text(label),
      );

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

  /// The commission breakdown, or the plain fare — never a computed guess.
  ///
  /// `driverEarnings`/`platformCommission` come straight from the backend
  /// (courier-view.ts) and are null until this delivery's payment actually
  /// settles. Until then there is no real split to show, so this falls back
  /// to the single fare row exactly as before rather than inventing one.
  List<Widget> _earningsRows(CourierRequest r) {
    if (r.driverEarnings == null) {
      final rows = <Widget>[
        _row(r.finalFare != null ? 'Final fare' : 'Estimated fare',
            Currency.format(r.finalFare ?? r.estimatedFare, decimals: 0)),
      ];
      if (r.status == 'DELIVERED') {
        rows.add(const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text('Payment pending — earnings will show once it settles.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ));
      }
      return rows;
    }

    final commission = r.platformCommission ?? 0;
    // Reconstructs the exact gross that was commissioned (finalFare) from the
    // backend's own split — never a value this app computed independently.
    final grossFare = r.driverEarnings! + commission;
    final pct = r.commissionRate != null ? ' (${(r.commissionRate! * 100).round()}%)' : '';

    return [
      _earningsRow('Customer paid', Currency.format(grossFare, decimals: 0)),
      if (commission > 0) _earningsRow('RavelGo commission$pct', '-${Currency.format(commission, decimals: 0)}', muted: true),
      if (r.cancellationFee != null && r.cancellationFee! > 0)
        _earningsRow('Cancellation fee', '+${Currency.format(r.cancellationFee!, decimals: 0)}', accent: AppColors.success),
      const SizedBox(height: 4),
      AppComponents.divider(),
      const SizedBox(height: 4),
      _earningsRow('Your earnings', Currency.format(r.driverEarnings!, decimals: 0), bold: true),
    ];
  }

  Widget _earningsRow(String label, String value, {bool bold = false, bool muted = false, Color? accent}) {
    final color = accent ?? (muted ? AppColors.textMuted : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
          Text(value, style: TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
          ],
        ),
      );

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  String _formatDateTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    final min = d.minute.toString().padLeft(2, '0');
    return '${d.month}/${d.day}/${d.year} $h:$min $ampm';
  }
}
