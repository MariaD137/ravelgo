enum TicketStatus { open, inProgress, resolved }

TicketStatus ticketStatusFromApi(String value) {
  switch (value) {
    case 'IN_PROGRESS':
      return TicketStatus.inProgress;
    case 'RESOLVED':
      return TicketStatus.resolved;
    case 'OPEN':
    default:
      return TicketStatus.open;
  }
}

String ticketStatusToApi(TicketStatus status) {
  switch (status) {
    case TicketStatus.open:
      return 'OPEN';
    case TicketStatus.inProgress:
      return 'IN_PROGRESS';
    case TicketStatus.resolved:
      return 'RESOLVED';
  }
}

class SupportTicket {
  final String id;
  final String from;
  final String subject;
  final String category;
  final TicketStatus status;
  final DateTime createdAt;

  const SupportTicket({
    required this.id,
    required this.from,
    required this.subject,
    required this.category,
    required this.status,
    required this.createdAt,
  });

  /// Built from GET /api/support-tickets (Admin, paginated).
  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return SupportTicket(
      id: json['id'] as String,
      from: user == null ? '(unknown)' : '${user['firstName']} ${user['lastName']}',
      subject: json['subject'] as String,
      category: json['category'] as String,
      status: ticketStatusFromApi(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
