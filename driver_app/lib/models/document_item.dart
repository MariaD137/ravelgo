enum DocumentStatus { approved, pending, expiringSoon, rejected, notUploaded }

class DocumentItem {
  final String title;
  final DocumentStatus status;
  final DateTime? expiryDate;

  const DocumentItem({required this.title, required this.status, this.expiryDate});
}

final List<DocumentItem> mockDocuments = [
  DocumentItem(title: "Driver's License", status: DocumentStatus.approved, expiryDate: DateTime(2027, 4, 12)),
  DocumentItem(title: "Vehicle Registration (Car Papers)", status: DocumentStatus.expiringSoon, expiryDate: DateTime(2026, 8, 2)),
  DocumentItem(title: "Roadworthiness Certificate", status: DocumentStatus.approved, expiryDate: DateTime(2027, 1, 20)),
  DocumentItem(title: "Insurance Certificate", status: DocumentStatus.pending),
  DocumentItem(title: "Background Check", status: DocumentStatus.approved),
  DocumentItem(title: "Proof of Address", status: DocumentStatus.notUploaded),
];
