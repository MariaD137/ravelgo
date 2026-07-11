import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/document_item.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';

class MyDocumentsScreen extends StatelessWidget {
  const MyDocumentsScreen({super.key});

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
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: mockDocuments.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final d = mockDocuments[i];
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
