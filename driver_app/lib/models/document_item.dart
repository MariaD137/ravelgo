enum DocumentStatus { approved, pending, expiringSoon, rejected, notUploaded }

DocumentStatus _statusFromBackend(String? raw) {
  switch (raw) {
    case 'APPROVED':
      return DocumentStatus.approved;
    case 'PENDING':
      return DocumentStatus.pending;
    case 'EXPIRING_SOON':
      return DocumentStatus.expiringSoon;
    case 'REJECTED':
      return DocumentStatus.rejected;
    default:
      return DocumentStatus.notUploaded;
  }
}

/// A driver's own document — parsed from GET /api/documents/me's real
/// DriverDocument rows (status is Admin-controlled via
/// PATCH /documents/:id/review, never set client-side).
class DocumentItem {
  final String id;
  final String title;
  final DocumentStatus status;
  final DateTime? expiryDate;

  const DocumentItem({required this.id, required this.title, required this.status, this.expiryDate});

  factory DocumentItem.fromJson(Map<String, dynamic> json) {
    final expiry = json['expiryDate'] as String?;
    return DocumentItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Document',
      status: _statusFromBackend(json['status'] as String?),
      expiryDate: expiry == null ? null : DateTime.tryParse(expiry),
    );
  }
}
