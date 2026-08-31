import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class DriverDetailScreen extends StatefulWidget {
  final String driverId;
  const DriverDetailScreen({super.key, required this.driverId});

  @override
  State<DriverDetailScreen> createState() => _DriverDetailScreenState();
}

class _DriverDetailScreenState extends State<DriverDetailScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  AdminDriver? _driver;

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
      final d = await AdminApi.driver(widget.driverId);
      if (!mounted) return;
      setState(() {
        _driver = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String okMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMessage)));
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _docColor(String s) {
    switch (s) {
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.danger;
      case 'EXPIRING_SOON':
        return AppColors.warning;
      default:
        return AppColors.warning;
    }
  }

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_driver?.name.isNotEmpty == true ? _driver!.name : 'Driver')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
                      TextButton(onPressed: _load, child: const Text('Try again')),
                    ]),
                  ),
                )
              : _content()),
    );
  }

  Widget _content() {
    final d = _driver!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppComponents.cardDecoration(),
          child: Column(
            children: [
              _kv("Email", d.email.isEmpty ? '—' : d.email),
              const SizedBox(height: 8),
              _kv("Status", _label(d.status)),
              const SizedBox(height: 8),
              _kv("Online", d.isOnline ? "Yes" : "No"),
              const SizedBox(height: 8),
              _kv("Rating", "★ ${d.rating.toStringAsFixed(1)}  ·  ${d.totalTrips} trips"),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AppComponents.sectionTitle("Document verification"),
        if (d.documents.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text("This driver hasn't uploaded any documents yet.",
                style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          ...d.documents.map((doc) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: AppComponents.cardDecoration(),
                  child: Row(
                    children: [
                      Icon(doc.status == 'APPROVED' ? Icons.check_circle : Icons.pending_outlined,
                          color: _docColor(doc.status), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(doc.title, style: const TextStyle(fontSize: 13.5)),
                            Text(_label(doc.status),
                                style: TextStyle(fontSize: 11, color: _docColor(doc.status))),
                          ],
                        ),
                      ),
                      if (doc.status != 'APPROVED')
                        IconButton(
                          tooltip: 'Approve',
                          icon: const Icon(Icons.check, color: AppColors.success),
                          onPressed: _busy ? null : () => _run(() => AdminApi.reviewDocument(doc.id, 'APPROVED'), 'Document approved'),
                        ),
                      if (doc.status != 'REJECTED')
                        IconButton(
                          tooltip: 'Reject',
                          icon: const Icon(Icons.close, color: AppColors.danger),
                          onPressed: _busy ? null : () => _run(() => AdminApi.reviewDocument(doc.id, 'REJECTED'), 'Document rejected'),
                        ),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 20),
        if (_busy) const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
        Row(
          children: [
            Expanded(
              child: AppComponents.outlineButton(
                text: d.status == 'SUSPENDED' ? "Reactivate" : "Suspend driver",
                color: d.status == 'SUSPENDED' ? AppColors.success : AppColors.danger,
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => AdminApi.setDriverStatus(d.id, d.status == 'SUSPENDED' ? 'ACTIVE' : 'SUSPENDED'),
                        d.status == 'SUSPENDED' ? 'Driver reactivated' : 'Driver suspended'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppComponents.primaryButton(
                text: d.status == 'ACTIVE' ? "Approved" : "Approve driver",
                onPressed: (_busy || d.status == 'ACTIVE')
                    ? null
                    : () => _run(() => AdminApi.setDriverStatus(d.id, 'ACTIVE'), 'Driver approved'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _kv(String k, String v) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k),
          Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      );
}
