import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

/// Short-stay listing detail: host info, listing status, and the real
/// bookings made against it (GET /api/stays/:id/bookings, admin-only).
class StayDetailScreen extends StatefulWidget {
  final StayListing listing;
  const StayDetailScreen({super.key, required this.listing});

  @override
  State<StayDetailScreen> createState() => _StayDetailScreenState();
}

class _StayDetailScreenState extends State<StayDetailScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  late StayListing _listing = widget.listing;
  List<StayBooking> _bookings = const [];

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
      final results = await Future.wait([
        AdminApi.stay(widget.listing.id),
        AdminApi.stayBookings(widget.listing.id),
      ]);
      if (!mounted) return;
      setState(() {
        _listing = results[0] as StayListing;
        _bookings = results[1] as List<StayBooking>;
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

  Future<void> _decide(String status) async {
    final approve = status == 'APPROVED';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Approve this listing?' : 'Reject this listing?'),
        content: Text(approve
            ? '"${_listing.title}" will become visible to guests for booking.'
            : '"${_listing.title}" will be hidden from guests.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: approve ? null : ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await AdminApi.setStayStatus(_listing.id, status);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(approve ? 'Listing approved' : 'Listing rejected')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'APPROVED':
      case 'CONFIRMED':
        return AppColors.success;
      case 'REJECTED':
      case 'CANCELLED':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_listing.title.isEmpty ? 'Listing' : _listing.title),
        actions: [
      // A-5: these screens load once and then sit on whatever they fetched.
      // Approvals, suspensions and payouts are worked in parallel by several
      // admins, so a stale detail view is a decision made on old facts; there
      // was no way to re-read it short of backing out and reopening.
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: (_loading || _busy) ? null : _load,
          ),
        ],
      ),
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
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final pending = _listing.status == 'PENDING_APPROVAL';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppComponents.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Status", style: TextStyle(color: AppColors.textSecondary)),
                  AppComponents.badge(_label(_listing.status), color: _statusColor(_listing.status)),
                ],
              ),
              const Divider(height: 20),
              _row("Address", _listing.address),
              _row("Price/night", Currency.format(_listing.pricePerNight, decimals: 0)),
              _row("Max guests", "${_listing.maxGuests}"),
              if (_listing.description?.isNotEmpty == true) _row("Description", _listing.description!),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppComponents.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Host", style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _row("Name", _listing.host != null && _listing.host!.name.isNotEmpty ? _listing.host!.name : "—"),
              _row("Email", _listing.host?.email?.isNotEmpty == true ? _listing.host!.email! : "—"),
            ],
          ),
        ),
        if (pending) ...[
          const SizedBox(height: 20),
          if (_busy) const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
          Row(
            children: [
              Expanded(
                child: AppComponents.outlineButton(
                  text: "Approve",
                  color: AppColors.success,
                  onPressed: _busy ? null : () => _decide('APPROVED'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppComponents.outlineButton(
                  text: "Reject",
                  color: AppColors.danger,
                  onPressed: _busy ? null : () => _decide('REJECTED'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        AppComponents.sectionTitle("Bookings (${_bookings.length})"),
        if (_bookings.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text("No bookings yet.", style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          ..._bookings.map((b) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: AppComponents.cardDecoration(),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.guestName.isEmpty ? (b.guestEmail ?? "Guest") : b.guestName,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text("${formatFriendlyDate(b.checkIn)} → ${formatFriendlyDate(b.checkOut)} · ${b.nights} night${b.nights == 1 ? '' : 's'}",
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AppComponents.badge(_label(b.status), color: _statusColor(b.status)),
                        const SizedBox(height: 4),
                        Text(Currency.format(b.totalPrice, decimals: 0), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
