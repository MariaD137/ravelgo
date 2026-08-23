import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/driver_record.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/document_api.dart';
import 'package:ravelgo_admin/services/api/driver_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class DriverDetailScreen extends StatefulWidget {
  final String driverId;
  final DriverApi? driverApi;
  final DocumentApi? documentApi;
  const DriverDetailScreen({super.key, required this.driverId, this.driverApi, this.documentApi});

  @override
  State<DriverDetailScreen> createState() => _DriverDetailScreenState();
}

class _DriverDetailScreenState extends State<DriverDetailScreen> {
  late final DriverApi _driverApi = widget.driverApi ?? DriverApi(ApiClient());
  late final DocumentApi _documentApi = widget.documentApi ?? DocumentApi(ApiClient());

  Future<DriverRecord>? _future;
  bool _mutating = false;
  // Set to true whenever a mutation actually reaches the backend and
  // succeeds — the list screen uses this to know whether to refresh itself
  // rather than trusting local state to reflect what the server did.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<DriverRecord> _load() async {
    final json = await _driverApi.getById(widget.driverId);
    return DriverRecord.fromJson(json);
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _setStatus(DriverStatus newStatus) async {
    setState(() => _mutating = true);
    try {
      await _driverApi.setStatus(widget.driverId, driverStatusToApi(newStatus));
      _changed = true;
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(newStatus == DriverStatus.suspended ? 'Driver suspended' : 'Driver reactivated')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update driver: $err')));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _reviewDocument(DriverDocumentRecord doc, String status) async {
    setState(() => _mutating = true);
    try {
      await _documentApi.review(doc.id, status);
      _changed = true;
      if (!mounted) return;
      await _reload();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update document: $err')));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Driver')),
        body: FutureBuilder<DriverRecord>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Failed to load driver: ${snapshot.error}'));
            }
            final d = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppComponents.cardDecoration(),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("ID"),
                          Text(d.id, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Name"),
                          Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Email"),
                          Text(d.email, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Vehicle"),
                          Text(d.vehicle, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Rating"),
                          Text("★ ${d.rating}  ·  ${d.totalTrips} trips", style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Subscription"),
                          AppComponents.badge(d.subscriptionActive ? "Active" : "Inactive", color: d.subscriptionActive ? AppColors.success : AppColors.danger),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                AppComponents.sectionTitle("Document verification"),
                if (d.documents.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("No documents uploaded yet.", style: TextStyle(color: Colors.black54)),
                  ),
                ...d.documents.map((doc) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: AppComponents.cardDecoration(),
                        child: Row(
                          children: [
                            Icon(doc.isApproved ? Icons.check_circle : Icons.pending_outlined, color: doc.isApproved ? AppColors.success : AppColors.warning, size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text('${doc.title} (${doc.status})', style: const TextStyle(fontSize: 13.5))),
                            if (!doc.isApproved)
                              TextButton(
                                onPressed: _mutating ? null : () => _reviewDocument(doc, 'APPROVED'),
                                child: const Text("Approve"),
                              ),
                          ],
                        ),
                      ),
                    )),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: AppComponents.outlineButton(
                        text: _mutating ? "Working…" : (d.status == DriverStatus.suspended ? "Reactivate" : "Suspend driver"),
                        color: d.status == DriverStatus.suspended ? AppColors.success : AppColors.danger,
                        onPressed: _mutating
                            ? null
                            : () => _setStatus(d.status == DriverStatus.suspended ? DriverStatus.active : DriverStatus.suspended),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
