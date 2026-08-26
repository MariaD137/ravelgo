import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_driver_app/models/document_item.dart';
import 'package:ravelgo_driver_app/services/auth_session.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/services/image_picker_helper.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';
import 'package:url_launcher/url_launcher.dart';

enum _LoadState { loading, loaded, error }

// Driver-level document types only — vehicle-scoped ones (registration,
// insurance, inspection, roadworthiness) live on VehicleDetailScreen
// instead, since they belong to a specific vehicle.
const _driverDocumentTypes = [
  DriverDocumentType.driversLicense,
  DriverDocumentType.backgroundCheck,
  DriverDocumentType.proofOfAddress,
];

class MyDocumentsScreen extends StatefulWidget {
  final bool embedded;
  // Injectable for tests; production call sites omit this and get the real
  // dotenv-configured client.
  final DriverApi? api;
  const MyDocumentsScreen({super.key, this.embedded = false, this.api});

  @override
  State<MyDocumentsScreen> createState() => _MyDocumentsScreenState();
}

class _MyDocumentsScreenState extends State<MyDocumentsScreen> {
  late final DriverApi _api = widget.api ??
      DriverApi(baseUrl: dotenv.env['API_BASE_URL'] ?? '', authTokenProvider: const CognitoAuthTokenProvider());

  _LoadState _state = _LoadState.loading;
  List<DriverDocument> _documents = [];
  String _errorMessage = "Unable to load your documents";
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final documents = await _api.fetchDocuments();
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _state = _LoadState.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is DriverApiException ? e.message : "Unable to load your documents";
        _state = _LoadState.error;
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _uploadOrReplace(DriverDocumentType type, DriverDocument? existing) async {
    final picked = await pickImage(context);
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      if (existing != null && existing.status == DocumentStatus.rejected) {
        await _api.resubmitDocument(
          documentId: existing.id,
          bytes: picked.bytes,
          fileName: picked.fileName,
          contentType: picked.contentType,
        );
      } else {
        await _api.uploadDocument(
          bytes: picked.bytes,
          fileName: picked.fileName,
          contentType: picked.contentType,
          title: driverDocumentTypeLabel(type),
          documentType: type,
        );
      }
      await _load();
    } catch (e) {
      _showError(e is DriverApiException ? e.message : "Upload failed");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _view(DriverDocument doc) async {
    try {
      final url = await _api.fetchDocumentViewUrl(doc.id);
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showError("Unable to open this document");
      }
    } catch (e) {
      _showError(e is DriverApiException ? e.message : "Unable to open this document");
    }
  }

  Color _statusColor(DocumentStatus s) {
    switch (s) {
      case DocumentStatus.approved:
        return AppColors.success;
      case DocumentStatus.pending:
        return AppColors.primaryDark;
      case DocumentStatus.expiringSoon:
        return Colors.orange;
      case DocumentStatus.rejected:
        return AppColors.danger;
      case DocumentStatus.notUploaded:
        return Colors.grey;
    }
  }

  String _statusLabel(DocumentStatus s) {
    switch (s) {
      case DocumentStatus.approved:
        return "Approved";
      case DocumentStatus.pending:
        return "Under review";
      case DocumentStatus.expiringSoon:
        return "Expiring soon";
      case DocumentStatus.rejected:
        return "Rejected";
      case DocumentStatus.notUploaded:
        return "Not uploaded";
    }
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const Center(child: Padding(padding: EdgeInsets.only(top: 60), child: Column(
          children: [CircularProgressIndicator(), SizedBox(height: 12), Text("Loading your documents...", style: TextStyle(color: Colors.black54))],
        )));
      case _LoadState.error:
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Text("Unable to load your documents", style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(_errorMessage, style: const TextStyle(fontSize: 12.5, color: Colors.black54), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              AppComponents.outlineButton(text: "Try again", onPressed: _load),
            ],
          ),
        );
      case _LoadState.loaded:
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _driverDocumentTypes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final type = _driverDocumentTypes[i];
              final matches = _documents.where((d) => d.documentType == type && d.vehicleId == null).toList();
              final doc = matches.isEmpty ? null : matches.first;
              final status = doc?.status ?? DocumentStatus.notUploaded;

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: AppComponents.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(driverDocumentTypeLabel(type), style: const TextStyle(fontWeight: FontWeight.w600))),
                        AppComponents.badge(_statusLabel(status), color: _statusColor(status)),
                      ],
                    ),
                    if (doc?.expiryDate != null) ...[
                      const SizedBox(height: 4),
                      Text("Expires ${formatShortDate(doc!.expiryDate!)}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                    if (status == DocumentStatus.rejected && doc?.rejectionReason != null) ...[
                      const SizedBox(height: 6),
                      Text("Reason: ${doc!.rejectionReason}", style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (doc != null && doc.hasFile)
                          TextButton(onPressed: _busy ? null : () => _view(doc), child: const Text("View")),
                        TextButton(
                          onPressed: _busy ? null : () => _uploadOrReplace(type, doc),
                          child: Text(doc == null || !doc.hasFile ? "Upload" : "Replace"),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("My Documents")), body: body);
  }
}
