import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

/// Real rider detail: loads GET /api/riders/:id (profile + recent trips) and
/// suspends/reinstates via the same PATCH the list screen uses. Pops `true`
/// when the status changed so the list can refresh.
class RiderDetailScreen extends StatefulWidget {
  final AdminRider rider;
  const RiderDetailScreen({super.key, required this.rider});

  @override
  State<RiderDetailScreen> createState() => _RiderDetailScreenState();
}

class _RiderDetailScreenState extends State<RiderDetailScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  AdminRiderDetail? _detail;
  late bool _suspended = widget.rider.suspended;

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
      final detail = await AdminApi.rider(widget.rider.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _suspended = detail.suspended;
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

  Future<void> _toggleSuspended() async {
    final name = widget.rider.name.isEmpty ? widget.rider.email : widget.rider.name;
    final suspend = !_suspended;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(suspend ? 'Suspend this rider?' : 'Reinstate this rider?'),
        content: Text(suspend
            ? '$name will no longer be able to sign in or request rides.'
            : '$name will regain full access to their account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: suspend ? ElevatedButton.styleFrom(backgroundColor: AppColors.danger) : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(suspend ? 'Suspend' : 'Reinstate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await AdminApi.setRiderSuspended(widget.rider.id, suspend);
      if (!mounted) return;
      setState(() => _suspended = suspend);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(suspend ? 'Rider suspended' : 'Rider reinstated')));
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'COMPLETED':
        return AppColors.success;
      case 'CANCELLED':
      case 'DISPUTED':
        return AppColors.danger;
      default:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rider.name.isEmpty ? widget.rider.email : widget.rider.name),
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
    if (_error != null || _detail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'Rider not found', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final d = _detail!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppComponents.cardDecoration(),
          child: Column(
            children: [
              _row("Email", d.email),
              _row("Phone", d.phoneNumber?.isNotEmpty == true ? d.phoneNumber! : "Not provided"),
              _row("Loyalty member", d.isLoyaltyMember ? "Yes" : "No"),
              _row("Joined", formatFriendlyDate(d.createdAt)),
              _row("Status", _suspended ? "Suspended" : "Active"),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_busy) const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
        AppComponents.outlineButton(
          text: _suspended ? "Reinstate account" : "Suspend account",
          color: _suspended ? AppColors.success : AppColors.danger,
          onPressed: _busy ? null : _toggleSuspended,
        ),
        const SizedBox(height: 24),
        AppComponents.sectionTitle("Recent trips"),
        if (d.recentTrips.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text("No trips yet.", style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          ...d.recentTrips.map((t) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: AppComponents.cardDecoration(),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${t.pickup} → ${t.destination}",
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(formatFriendlyDate(t.requestedAt), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AppComponents.badge(t.status, color: _statusColor(t.status)),
                        const SizedBox(height: 4),
                        Text(Currency.format(t.fare, decimals: 0), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
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
