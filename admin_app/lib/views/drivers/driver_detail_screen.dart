import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/widgets/reject_reason_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class DriverDetailScreen extends StatefulWidget {
  final String driverId;
  const DriverDetailScreen({super.key, required this.driverId});

  @override
  State<DriverDetailScreen> createState() => _DriverDetailScreenState();
}

class _DriverDetailScreenState extends State<DriverDetailScreen> {
  bool _loading = true;
  bool _busy = false;
  // Tracks which single document is mid signed-URL-fetch, so only that
  // document's button shows a spinner rather than blocking the whole screen.
  String? _viewingDocId;
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // Fetches a fresh signed URL and opens it — never reuses a previously
  // fetched URL, so there is nothing to expire between clicks.
  Future<void> _viewDocument(AdminDocument doc) async {
    if (_viewingDocId != null) return;
    setState(() => _viewingDocId = doc.id);
    try {
      final url = await AdminApi.documentSignedUrl(widget.driverId, doc.id);
      final uri = Uri.tryParse(url);
      if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _snack('Could not open this document.');
      }
    } catch (e) {
      final msg = e is ApiException ? e.message : 'Could not open this document.';
      _snack(msg);
    } finally {
      if (mounted) setState(() => _viewingDocId = null);
    }
  }

  Future<void> _rejectDocument(AdminDocument doc) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => RejectReasonDialog(itemLabel: doc.title),
    );
    if (reason == null) return; // cancelled
    await _run(() => AdminApi.reviewDocument(doc.id, 'REJECTED', rejectionReason: reason), 'Document rejected');
  }

  String _vehicleLabel(AdminDriverVehicle v) => '${v.brand} ${v.model} (${v.plateNumber})'.trim();

  Future<void> _approveVehicle(AdminDriverVehicle v) async {
    await _run(() => AdminApi.setVehicleApproval(v.id, 'APPROVED'), 'Vehicle approved');
  }

  Future<void> _rejectVehicle(AdminDriverVehicle v) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => RejectReasonDialog(itemLabel: _vehicleLabel(v)),
    );
    if (reason == null) return; // cancelled
    await _run(
      () => AdminApi.setVehicleApproval(v.id, 'REJECTED', rejectionReason: reason),
      'Vehicle rejected',
    );
  }

  /// Approving the driver is the ONE action that changes Driver.status — the
  /// field the driver app reads and the backend's go-online gate checks.
  /// Approving documents individually never does (see backend
  /// documents.routes.ts vs drivers.routes.ts). The backend deliberately does
  /// not block approval on document state, so this confirmation shows the
  /// reviewer the real per-document outcomes before they commit.
  Future<void> _approveDriver(AdminDriver d) async {
    final unresolved = d.documents.where((doc) => doc.status != 'APPROVED').toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve this driver?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'They will be able to go online and receive trips immediately.',
              style: TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            if (d.documents.isEmpty)
              const Text(
                'This driver has not uploaded any documents.',
                style: TextStyle(fontSize: 13, color: AppColors.danger),
              )
            else if (unresolved.isEmpty)
              Text(
                'All ${d.documents.length} uploaded document(s) are approved.',
                style: const TextStyle(fontSize: 13, color: AppColors.success),
              )
            else ...[
              Text(
                '${unresolved.length} of ${d.documents.length} document(s) not yet approved:',
                style: const TextStyle(fontSize: 13, color: AppColors.warning),
              ),
              const SizedBox(height: 4),
              for (final doc in unresolved)
                Text('• ${doc.title} — ${_label(doc.status)}', style: const TextStyle(fontSize: 12.5)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Approve driver')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => AdminApi.setDriverStatus(d.id, 'ACTIVE'), 'Driver approved');
  }

  Future<void> _callDriver(String phoneNumber) async {
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    if (!await launchUrl(uri)) _snack('Could not start a call.');
  }

  Future<void> _emailDriver(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (!await launchUrl(uri)) _snack('Could not open an email draft.');
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

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_driver?.name.isNotEmpty == true ? _driver!.name : 'Driver'),
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
    final phone = d.phoneNumber?.trim();
    final hasPhone = phone != null && phone.isNotEmpty;
    final hasEmail = d.email.isNotEmpty;
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
              _kv("Phone", hasPhone ? phone : 'Not provided'),
              const SizedBox(height: 8),
              _kv("Status", _label(d.status)),
              const SizedBox(height: 8),
              _kv("Online", d.isOnline ? "Yes" : "No"),
              const SizedBox(height: 8),
              _kv("Rating", "★ ${d.rating.toStringAsFixed(1)}  ·  ${d.totalTrips} trips"),
            ],
          ),
        ),
        if (hasPhone || hasEmail) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (hasPhone)
                Expanded(
                  child: AppComponents.outlineButton(
                    text: 'Call driver',
                    onPressed: () => _callDriver(phone),
                  ),
                ),
              if (hasPhone && hasEmail) const SizedBox(width: 12),
              if (hasEmail)
                Expanded(
                  child: AppComponents.outlineButton(
                    text: 'Email driver',
                    onPressed: () => _emailDriver(d.email),
                  ),
                ),
            ],
          ),
        ],
        if (d.status == 'PENDING_REVIEW') ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.warning),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This application is awaiting a decision. Reviewing documents below records each '
                    'outcome for the driver, but only "Approve driver" lets them go online.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        AppComponents.sectionTitle("Vehicles"),
        if (d.vehicles.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text("This driver hasn't added any vehicles yet.",
                style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          ...d.vehicles.map((v) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: AppComponents.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (v.photoUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                v.photoUrl!,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.directions_car, color: AppColors.textSecondary),
                              ),
                            )
                          else
                            const Icon(Icons.directions_car_outlined, color: AppColors.textSecondary, size: 32),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${v.year} ${v.brand} ${v.model}'.trim(),
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                Text('${v.colour} · ${v.plateNumber}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                Text(_label(v.approvalStatus), style: TextStyle(fontSize: 11, color: _docColor(v.approvalStatus))),
                                Text(
                                  'Class: ${v.vehicleClass ?? "Unclassified"}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          if (v.isPrimary) AppComponents.badge("Primary", color: AppColors.info),
                          if (v.listedForRental) AppComponents.badge("Rental", color: AppColors.success),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (v.approvalStatus != 'APPROVED')
                            Expanded(
                              child: AppComponents.outlineButton(
                                text: 'Approve',
                                color: AppColors.success,
                                onPressed: _busy ? null : () => _approveVehicle(v),
                              ),
                            ),
                          if (v.approvalStatus != 'APPROVED' && v.approvalStatus != 'REJECTED')
                            const SizedBox(width: 8),
                          if (v.approvalStatus != 'REJECTED')
                            Expanded(
                              child: AppComponents.outlineButton(
                                text: 'Reject',
                                color: AppColors.danger,
                                onPressed: _busy ? null : () => _rejectVehicle(v),
                              ),
                            ),
                        ],
                      ),
                      if (v.approvalStatus == 'REJECTED' && (v.rejectionReason?.isNotEmpty ?? false))
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Reason: ${v.rejectionReason}',
                            style: const TextStyle(fontSize: 12, color: AppColors.danger),
                          ),
                        ),
                    ],
                  ),
                ),
              )),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                                Text(
                                  doc.expiryDate == null ? 'Expiry: Not provided' : 'Expires: ${_formatDate(doc.expiryDate!)}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          if (doc.fileKey != null)
                            IconButton(
                              tooltip: 'View document',
                              icon: _viewingDocId == doc.id
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.visibility_outlined, color: AppColors.info),
                              onPressed: _viewingDocId != null ? null : () => _viewDocument(doc),
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
                              onPressed: _busy ? null : () => _rejectDocument(doc),
                            ),
                        ],
                      ),
                      if (doc.status == 'REJECTED' && (doc.rejectionReason?.isNotEmpty ?? false))
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 30),
                          child: Text(
                            'Reason: ${doc.rejectionReason}',
                            style: const TextStyle(fontSize: 12, color: AppColors.danger),
                          ),
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
                onPressed: (_busy || d.status == 'ACTIVE') ? null : () => _approveDriver(d),
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
