import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/widgets/empty_state.dart';
import 'package:ravelgo_driver_app/widgets/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

class MyDocumentsScreen extends StatefulWidget {
  const MyDocumentsScreen({super.key});

  @override
  State<MyDocumentsScreen> createState() => _MyDocumentsScreenState();
}

class _MyDocumentsScreenState extends State<MyDocumentsScreen> {
  static const _docTypes = [
    "Driver's License",
    "Vehicle Registration (Car Papers)",
    "Roadworthiness Certificate",
    "Insurance Certificate",
    "Proof of Address",
  ];

  bool _loading = true;
  bool _uploading = false;
  String? _error;
  List<DriverDocument> _docs = const [];
  String? _openingDocId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _contentTypeFor(XFile f) {
    final ct = f.mimeType ?? '';
    if (ct.isNotEmpty) return ct;
    final n = f.name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.heic')) return 'image/heic';
    if (n.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg';
  }

  Future<void> _addDocument() async {
    // 1. Choose which document this is.
    final title = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Which document?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final t in _docTypes)
              ListTile(title: Text(t), onTap: () => Navigator.pop(ctx, t)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (title == null || !mounted) return;

    // 2. Pick an image of the document.
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open picker: $e')));
      return;
    }
    if (picked == null || !mounted) return;

    // 3. Upload it.
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      await DriverApi.uploadDocument(
        title: title,
        fileName: picked.name,
        contentType: _contentTypeFor(picked),
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document submitted for review.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = describeApiFailure(e, what: 'your document');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docs = await DriverApi.myDocuments();
      if (!mounted) return;
      setState(() {
        _docs = docs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiFailure(e, what: 'your documents');
        _loading = false;
      });
    }
  }

  /// Opens a real, freshly-signed URL for a document this driver actually
  /// uploaded (GET /api/documents/:id/url) — never a public/permanent link,
  /// never another driver's document (the backend enforces ownership; the
  /// only thing gating this client-side is that NOT_UPLOADED documents have
  /// no file to view at all).
  Future<void> _viewDocument(DriverDocument doc) async {
    setState(() => _openingDocId = doc.id);
    try {
      final url = await DriverApi.myDocumentUrl(doc.id);
      final uri = Uri.tryParse(url);
      if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open this document.');
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : 'Could not open this document. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _openingDocId = null);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'APPROVED':
        return AppColors.success;
      case 'PENDING':
        return AppColors.primaryDark;
      case 'EXPIRING_SOON':
        return AppColors.warning;
      case 'REJECTED':
        return AppColors.danger;
      default:
        return AppColors.textMuted;
    }
  }

  String _label(String s) {
    switch (s) {
      case 'APPROVED':
        return 'Approved';
      case 'PENDING':
        return 'Under review';
      case 'EXPIRING_SOON':
        return 'Expiring soon';
      case 'REJECTED':
        return 'Rejected';
      default:
        return 'Not uploaded';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Documents")),
      body: _body(),
      // Uploading is only offered once the document list itself loaded —
      // i.e. the backend confirmed this token belongs to a driver with a
      // profile. Otherwise the S3 upload would succeed and POST /documents
      // would be refused, leaving an orphaned object and a confusing error.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_uploading || _loading || _error != null) ? null : _addDocument,
        icon: _uploading
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.upload_file),
        label: Text(_uploading ? 'Uploading…' : 'Add document'),
      ),
    );
  }

  Widget _body() {
    return AsyncBody(
      stateKey: _loading ? "loading" : (_error != null ? "error" : "data:${_docs.length}"),
      child: _loading
          ? const ShimmerList()
          : _error != null
              ? EmptyState(icon: Icons.cloud_off, title: "Couldn't load documents", subtitle: _error!, onRetry: _load)
              : _docs.isEmpty
                  ? const EmptyState(
                      icon: Icons.description_outlined,
                      title: "No documents on file yet",
                      subtitle: "Your uploaded documents and their approval status will appear here.",
                    )
                  : _docList(),
    );
  }

  Widget _docList() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _docs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final d = _docs[i];
          final hasFile = d.status != 'NOT_UPLOADED';
          final opening = _openingDocId == d.id;
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: (!hasFile || opening) ? null : () => _viewDocument(d),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AppComponents.cardDecoration(),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (d.expiryDate != null) ...[
                          const SizedBox(height: 4),
                          Text("Expires ${d.expiryDate!.toLocal().toString().split(' ').first}",
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                        if (hasFile) ...[
                          const SizedBox(height: 4),
                          const Text("Tap to view", style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                  if (opening)
                    const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    AppComponents.badge(_label(d.status), color: _statusColor(d.status)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
