import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/config/currency.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/deliveries/delivery_detail_screen.dart';
import 'package:ravelgo_driver_app/views/deliveries/delivery_proof_screen.dart';

/// Package delivery requests: browse unassigned ones to accept, and track the
/// ones this driver already accepted through to drop-off. Only an ACTIVE
/// (admin-approved) driver can browse or accept — the backend enforces the
/// same approval gate used for ride matching. Four tabs mirror the real
/// backend lifecycle (CourierStatus): Available (REQUESTED, unassigned),
/// Assigned (MATCHED to this driver), Active (PICKED_UP/IN_TRANSIT),
/// Completed (DELIVERED/CANCELLED) — never an invented grouping.
class DeliveriesScreen extends StatefulWidget {
  const DeliveriesScreen({super.key});

  @override
  State<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends State<DeliveriesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<CourierRequest> _available = const [];
  List<CourierRequest> _mine = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<CourierRequest> get _assigned => _mine.where((r) => r.status == 'MATCHED').toList();
  List<CourierRequest> get _active => _mine.where((r) => r.status == 'PICKED_UP' || r.status == 'IN_TRANSIT').toList();
  List<CourierRequest> get _completed => _mine.where((r) => r.status == 'DELIVERED' || r.status == 'CANCELLED').toList();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([DriverApi.availableDeliveries(), DriverApi.myDeliveries()]);
      if (!mounted) return;
      setState(() {
        _available = results[0];
        _mine = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 409
            ? 'Your account isn\'t approved for deliveries yet. You can go online for deliveries once an admin approves you.'
            : (e is ApiException && e.statusCode == 403
                ? 'Your account isn\'t set up as a driver yet.'
                : 'Could not load deliveries — check your connection.');
        _loading = false;
      });
    }
  }

  Future<void> _accept(CourierRequest r) async {
    setState(() => _busy = true);
    try {
      await DriverApi.acceptDelivery(r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery accepted.')));
      await _load();
      if (mounted) _tabs.animateTo(1);
    } catch (e) {
      if (!mounted) return;
      final isConflict = e is ApiException && e.statusCode == 409;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isConflict
            ? 'This delivery was just accepted by another driver.'
            : (e is ApiException ? e.message : e.toString())),
      ));
      if (isConflict) await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advance(CourierRequest r, String nextStatus) async {
    setState(() => _busy = true);
    try {
      await DriverApi.updateDeliveryStatus(r.id, nextStatus);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nextStatus == 'PICKED_UP' ? 'Marked picked up.' : 'On the way.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Completing a delivery requires proof (photo + recipient signature) — the
  /// backend rejects DELIVERED without both — so this opens the capture
  /// screen instead of flipping the status directly.
  Future<void> _completeDelivery(CourierRequest r) async {
    final updated = await Navigator.of(context).push<CourierRequest>(
      MaterialPageRoute(builder: (_) => DeliveryProofScreen(request: r)),
    );
    if (updated != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked delivered.')));
      await _load();
    }
  }

  Future<void> _openDetail(CourierRequest r) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DeliveryDetailScreen(deliveryId: r.id, initial: r)),
    );
    if (mounted) await _load();
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'DELIVERED':
        return AppColors.online;
      case 'IN_TRANSIT':
      case 'PICKED_UP':
        return AppColors.primaryDark;
      case 'CANCELLED':
        return AppColors.offline;
      default:
        return AppColors.warning;
    }
  }

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deliveries'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [Tab(text: 'Available'), Tab(text: 'Assigned'), Tab(text: 'Active'), Tab(text: 'Completed')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null
              ? _errorView()
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _availableList(),
                    _jobList(_assigned, emptyText: 'No deliveries assigned to you yet.'),
                    _jobList(_active, emptyText: 'No deliveries in progress.'),
                    _jobList(_completed, emptyText: 'No completed deliveries yet.'),
                  ],
                )),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 8),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );

  Widget _availableList() {
    if (_available.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No delivery requests waiting right now.', style: TextStyle(color: AppColors.textSecondary))),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _available.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = _available[i];
          return InkWell(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            onTap: () => _openDetail(r),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AppComponents.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.packageDescription, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('From: ${r.pickupAddress}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  Text('To: ${r.dropoffAddress}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  if (r.distanceKm != null)
                    Text('${r.distanceKm!.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(Currency.format(r.estimatedFare, decimals: 0), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      AppComponents.primaryButton(text: 'Accept', onPressed: _busy ? null : () => _accept(r)),
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

  Widget _jobList(List<CourierRequest> jobs, {required String emptyText}) {
    if (jobs.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(child: Text(emptyText, style: const TextStyle(color: AppColors.textSecondary))),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: jobs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = jobs[i];
          return InkWell(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            onTap: () => _openDetail(r),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AppComponents.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(r.packageDescription, style: const TextStyle(fontWeight: FontWeight.w700))),
                      AppComponents.badge(_label(r.status), color: _statusColor(r.status)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('From: ${r.pickupAddress}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  Text('To: ${r.dropoffAddress}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  // The customer's name is only shown once matched to THIS
                  // driver — privacy-appropriate, same rule the backend
                  // itself enforces on who can even fetch this record.
                  if (r.senderName != null)
                    Text('Customer: ${r.senderName}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  Text('Recipient: ${r.recipientName} · ${r.recipientPhone}',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(Currency.format(r.finalFare ?? r.estimatedFare, decimals: 0), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (r.status == 'MATCHED')
                        AppComponents.primaryButton(text: 'Mark picked up', onPressed: _busy ? null : () => _advance(r, 'PICKED_UP')),
                      if (r.status == 'PICKED_UP')
                        AppComponents.primaryButton(text: 'Start delivery', onPressed: _busy ? null : () => _advance(r, 'IN_TRANSIT')),
                      if (r.status == 'IN_TRANSIT')
                        AppComponents.primaryButton(text: 'Mark delivered', onPressed: _busy ? null : () => _completeDelivery(r)),
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
