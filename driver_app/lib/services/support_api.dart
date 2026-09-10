import 'package:ravelgo_driver_app/services/api_client.dart';

/// Mirrors user_app/lib/services/support_api.dart exactly — same backend
/// contract (POST/GET /api/support-tickets), same SupportTicket shape. The
/// backend scopes tickets by the authenticated caller's own User row
/// (backend/src/routes/support.routes.ts), so a driver only ever sees their
/// own tickets regardless of role — no separate driver-only ticket system.
class SupportTicket {
  final String id;
  final String subject;
  final String category;
  final String status;
  final DateTime createdAt;

  SupportTicket({
    required this.id,
    required this.subject,
    required this.category,
    required this.status,
    required this.createdAt,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> j) => SupportTicket(
        id: '${j['id']}',
        subject: '${j['subject'] ?? ''}',
        category: '${j['category'] ?? ''}',
        status: '${j['status'] ?? 'OPEN'}',
        createdAt: DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? DateTime.now(),
      );
}

class SupportApi {
  /// Open a support ticket. Reaches the same admin support queue user_app's
  /// riders use.
  static Future<SupportTicket> createTicket({required String subject, required String category}) async {
    final data = await ApiClient.post('/api/support-tickets', {'subject': subject, 'category': category});
    return SupportTicket.fromJson(data as Map<String, dynamic>);
  }

  /// The signed-in driver's own tickets, newest first.
  static Future<List<SupportTicket>> myTickets() async {
    final data = await ApiClient.get('/api/support-tickets/mine');
    final list = data as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(SupportTicket.fromJson).toList();
  }
}
