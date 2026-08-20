import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/document_item.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';

class MyDocumentsScreen extends StatefulWidget {
  const MyDocumentsScreen({super.key});

  @override
  State<MyDocumentsScreen> createState() => _MyDocumentsScreenState();
}

class _MyDocumentsScreenState extends State<MyDocumentsScreen> {
  bool _loading = true;
  String? _error;
  List<DocumentItem> _documents = [];

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  DocumentStatus _parseStatus(String? status) {
    switch (status) {
      case 'APPROVED':
        return DocumentStatus.approved;
      case 'PENDING':
        return DocumentStatus.pending;
      case 'EXPIRING_SOON':
        return DocumentStatus.expiringSoon;
      case 'REJECTED':
        return DocumentStatus.rejected;
      case 'NOT_UPLOADED':
      default:
        return DocumentStatus.notUploaded;
    }
  }

  DocumentItem _documentFromJson(Map<String, dynamic> json) {
    DateTime? expiry;
    if (json['expiryDate'] != null) {
      expiry = DateTime.tryParse(json['expiryDate'].toString());
    }
    return DocumentItem(
      title: json['title']?.toString() ?? '',
      status: _parseStatus(json['status']?.toString()),
      expiryDate: expiry,
    );
  }

  Future<void> _loadDocuments() async {
    try {
      final response = await ApiClient().get('/documents/me');
      if (!mounted) return;
      final List<dynamic> docList = response is List ? response : [];
      setState(() {
        _documents = docList.map((d) => _documentFromJson(Map<String, dynamic>.from(d))).toList();
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Failed to load documents', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        AppComponents.outlineButton(text: "Retry", onPressed: () { setState(() { _loading = true; _error = null; }); _loadDocuments(); }),
                      ],
                    ),
                  ),
                )
              : _documents.isEmpty
                  ? const Center(child: Text("No documents found", style: TextStyle(color: Colors.black54)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _documents.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final d = _documents[i];
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
  }
}
