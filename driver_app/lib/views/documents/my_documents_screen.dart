import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ravelgo_driver_app/models/document_item.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';

class MyDocumentsScreen extends StatefulWidget {
  const MyDocumentsScreen({super.key});

  @override
  State<MyDocumentsScreen> createState() => _MyDocumentsScreenState();
}

class _MyDocumentsScreenState extends State<MyDocumentsScreen> {
  late Future<List<DocumentItem>> _future;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<DocumentItem>> _load() async {
    final raw = await DriverSession.instance.documentApi.listMine();
    return raw.map(DocumentItem.fromJson).toList();
  }

  void _retry() => setState(() => _future = _load());

  Future<void> _addDocument() async {
    final titleController = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Document title'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Proof of Address'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, titleController.text.trim()),
            child: const Text('Choose file'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || !mounted) return;

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open the photo library: $err')));
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      await DriverSession.instance.documentApi.uploadAndRegister(
        title: title,
        bytes: bytes,
        fileName: picked.name,
        contentType: picked.mimeType ?? 'image/jpeg',
      );
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _future = _load();
      });
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: ${err.message}')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Documents")),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        onPressed: _uploading ? null : _addDocument,
        child: _uploading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
      ),
      body: FutureBuilder<List<DocumentItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'Could not load your documents.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _retry, child: const Text("Retry")),
                  ],
                ),
              ),
            );
          }
          final documents = snapshot.data ?? const [];
          if (documents.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("No documents uploaded yet.", style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _uploading ? null : _addDocument, child: const Text("Upload a document")),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              _retry();
              await _future;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: documents.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final d = documents[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppComponents.cardDecoration(),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            if (d.expiryDate != null)
                              Text("Expires ${formatShortDate(d.expiryDate!)}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                      AppComponents.badge(_statusLabel(d.status), color: _statusColor(d.status)),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
