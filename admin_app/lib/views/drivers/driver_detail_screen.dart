import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

enum _LoadState { loading, loaded, error }

class DriverDetailScreen extends StatefulWidget {
  final String driverId;
  final AdminApi api;
  const DriverDetailScreen({super.key, required this.driverId, required this.api});

  @override
  State<DriverDetailScreen> createState() => _DriverDetailScreenState();
}

class _DriverDetailScreenState extends State<DriverDetailScreen> {
  _LoadState _state = _LoadState.loading;
  AdminDriverDetail? _detail;
  String _errorMessage = "Unable to load this driver";
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final detail = await widget.api.fetchDriverDetail(widget.driverId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _state = _LoadState.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is AdminApiException ? e.message : "Unable to load this driver";
        _state = _LoadState.error;
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// A rejection reason is mandatory — this dialog is the only way to
  /// produce one, and returns null (cancelling the reject) if left blank.
  Future<String?> _askRejectionReason(String subject) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Reject $subject"),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Explain what's wrong so the driver can fix it",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(dialogContext, text);
            },
            child: const Text("Reject"),
          ),
        ],
      ),
    );
    return reason;
  }

  Future<void> _reviewDocument(AdminDocument doc, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await _askRejectionReason(doc.title);
      if (reason == null) return; // cancelled
    }
    setState(() => _busy = true);
    try {
      await widget.api.reviewDocument(doc.id, status: approve ? "APPROVED" : "REJECTED", rejectionReason: reason);
      await _load();
    } catch (e) {
      _showError(e is AdminApiException ? e.message : "Unable to review this document");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviewVehicle(AdminVehicle vehicle, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await _askRejectionReason("${vehicle.brand} ${vehicle.model}");
      if (reason == null) return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.reviewVehicle(vehicle.id, status: approve ? "APPROVED" : "REJECTED", reason: reason);
      await _load();
    } catch (e) {
      _showError(e is AdminApiException ? e.message : "Unable to review this vehicle");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _viewDocument(AdminDocument doc) async {
    try {
      final url = await widget.api.fetchDocumentViewUrl(doc.id);
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showError("Unable to open this document");
      }
    } catch (e) {
      _showError(e is AdminApiException ? e.message : "Unable to open this document");
    }
  }

  Future<void> _toggleSuspend() async {
    final detail = _detail!;
    final newStatus = detail.status == "SUSPENDED" ? "ACTIVE" : "SUSPENDED";
    setState(() => _busy = true);
    try {
      await widget.api.setDriverStatus(widget.driverId, newStatus);
      await _load();
    } catch (e) {
      _showError(e is AdminApiException ? e.message : "Unable to update this driver");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case "APPROVED":
        return AppColors.success;
      case "REJECTED":
        return AppColors.danger;
      case "EXPIRING_SOON":
        return AppColors.warning;
      case "PENDING":
      case "RESUBMISSION_REQUIRED":
        return AppColors.warning;
      case "NOT_UPLOADED":
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case "APPROVED":
        return "Approved";
      case "REJECTED":
        return "Rejected";
      case "EXPIRING_SOON":
        return "Expiring soon";
      case "PENDING":
        return "Pending review";
      case "RESUBMISSION_REQUIRED":
        return "Needs resubmission";
      case "NOT_UPLOADED":
        return "Not uploaded";
      default:
        return status;
    }
  }

  Widget _reviewButtons({required bool disabled, required VoidCallback onApprove, required VoidCallback onReject}) {
    return Row(
      children: [
        TextButton(onPressed: disabled ? null : onApprove, child: const Text("Approve")),
        TextButton(
          onPressed: disabled ? null : onReject,
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text("Reject"),
        ),
      ],
    );
  }

  Widget _buildDocumentCard(AdminDocument doc) {
    final needsReview = doc.status == "PENDING";
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: AppComponents.cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                AppComponents.badge(_statusLabel(doc.status), color: _statusColor(doc.status)),
              ],
            ),
            if (doc.status == "REJECTED" && doc.rejectionReason != null) ...[
              const SizedBox(height: 6),
              Text("Reason: ${doc.rejectionReason}", style: const TextStyle(fontSize: 12, color: AppColors.danger)),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                if (doc.hasFile) TextButton(onPressed: _busy ? null : () => _viewDocument(doc), child: const Text("View")),
                if (needsReview)
                  _reviewButtons(
                    disabled: _busy,
                    onApprove: () => _reviewDocument(doc, true),
                    onReject: () => _reviewDocument(doc, false),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleCard(AdminVehicle vehicle) {
    final needsReview = vehicle.verificationStatus == "PENDING";
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppComponents.cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text("${vehicle.brand} ${vehicle.model} · ${vehicle.plateNumber}", style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                AppComponents.badge(_statusLabel(vehicle.verificationStatus), color: _statusColor(vehicle.verificationStatus)),
              ],
            ),
            if (vehicle.verificationStatus == "REJECTED" && vehicle.verificationReason != null) ...[
              const SizedBox(height: 6),
              Text("Reason: ${vehicle.verificationReason}", style: const TextStyle(fontSize: 12, color: AppColors.danger)),
            ],
            if (vehicle.photos.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: vehicle.photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, i) {
                    final photo = vehicle.photos[i];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: photo.url != null
                          ? Image.network(photo.url!, width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined))
                          : Container(width: 72, height: 72, color: AppColors.background, child: const Icon(Icons.image_outlined)),
                    );
                  },
                ),
              ),
            ] else ...[
              const SizedBox(height: 6),
              const Text("No photos uploaded", style: TextStyle(fontSize: 12, color: Colors.black45)),
            ],
            if (needsReview) ...[
              const SizedBox(height: 8),
              _reviewButtons(
                disabled: _busy,
                onApprove: () => _reviewVehicle(vehicle, true),
                onReject: () => _reviewVehicle(vehicle, false),
              ),
            ],
            if (vehicle.documents.isNotEmpty) ...[
              const SizedBox(height: 10),
              AppComponents.sectionTitle("Documents"),
              ...vehicle.documents.map(_buildDocumentCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoaded(AdminDriverDetail d) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("ID"), Text(d.id, style: const TextStyle(fontWeight: FontWeight.w600))]),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Email"), Text(d.email, style: const TextStyle(fontWeight: FontWeight.w600))]),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [const Text("Rating"), Text("★ ${d.rating.toStringAsFixed(1)}  ·  ${d.totalTrips} trips", style: const TextStyle(fontWeight: FontWeight.w600))],
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
          AppComponents.sectionTitle("Vehicles"),
          if (d.vehicles.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: AppComponents.cardDecoration(),
              child: const Text("No vehicles on file", style: TextStyle(fontSize: 12.5, color: Colors.black54)),
            )
          else
            ...d.vehicles.map(_buildVehicleCard),
          const SizedBox(height: 12),
          AppComponents.sectionTitle("Driver documents"),
          if (d.documents.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: AppComponents.cardDecoration(),
              child: const Text("No documents on file", style: TextStyle(fontSize: 12.5, color: Colors.black54)),
            )
          else
            ...d.documents.map(_buildDocumentCard),
          const SizedBox(height: 20),
          AppComponents.outlineButton(
            text: d.status == "SUSPENDED" ? "Reactivate driver" : "Suspend driver",
            color: d.status == "SUSPENDED" ? AppColors.success : AppColors.danger,
            onPressed: _busy ? null : _toggleSuspend,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_detail?.name.isNotEmpty == true ? _detail!.name : "Driver")),
      body: switch (_state) {
        _LoadState.loading => const Center(child: CircularProgressIndicator()),
        _LoadState.error => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Unable to load this driver", style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(_errorMessage, style: const TextStyle(fontSize: 12.5, color: Colors.black54), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                AppComponents.outlineButton(text: "Try again", onPressed: _load),
              ],
            ),
          ),
        _LoadState.loaded => _buildLoaded(_detail!),
      },
    );
  }
}
