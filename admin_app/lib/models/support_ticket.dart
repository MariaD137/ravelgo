enum TicketStatus { open, inProgress, resolved }

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
}

final List<SupportTicket> mockTickets = [
  SupportTicket(id: "TCK-441", from: "Amaka Obi", subject: "Lost phone in trip RG-10201", category: "Lost item", status: TicketStatus.open, createdAt: DateTime.now().subtract(const Duration(hours: 2))),
  SupportTicket(id: "TCK-440", from: "Emeka Nwosu", subject: "Disputed cancellation charge", category: "Billing dispute", status: TicketStatus.inProgress, createdAt: DateTime.now().subtract(const Duration(hours: 9))),
  SupportTicket(id: "TCK-439", from: "Ngozi Peters", subject: "Driver took a longer route", category: "Trip complaint", status: TicketStatus.resolved, createdAt: DateTime.now().subtract(const Duration(days: 2))),
];
