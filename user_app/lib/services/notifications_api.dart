import 'package:ravelgo_user_app/services/api_client.dart';

/// A real, backend-persisted notification (see backend `Notification` model
/// and `notifications.routes.ts`) — never fabricated client-side. Every
/// notification the app shows was created from an actual event: a ride/
/// delivery/rental status change or a payment outcome.
class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final bool read;
  final String? referenceType; // e.g. "TRIP", "COURIER_REQUEST", "RENTAL_BOOKING"
  final String? referenceId;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.referenceType,
    this.referenceId,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: '${j['id']}',
        type: '${j['type'] ?? ''}',
        title: '${j['title'] ?? ''}',
        body: '${j['body'] ?? ''}',
        read: j['read'] == true,
        referenceType: j['referenceType']?.toString(),
        referenceId: j['referenceId']?.toString(),
        createdAt: DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? DateTime.now(),
      );
}

class NotificationPage {
  final List<AppNotification> items;
  final int unreadCount;
  final int total;
  NotificationPage({required this.items, required this.unreadCount, required this.total});
}

/// The signed-in user's own notifications, proxied through the RavelGo
/// backend (GET/PATCH/POST /api/notifications*). Ownership is enforced
/// server-side by the authenticated Cognito identity — there is no way to
/// pass another user's id through this client.
class NotificationsApi {
  static Future<NotificationPage> mine({int page = 1, int pageSize = 30}) async {
    final data = await ApiClient.get('/api/notifications?page=$page&pageSize=$pageSize') as Map<String, dynamic>;
    final list = (data['data'] as List? ?? const []).whereType<Map<String, dynamic>>().map(AppNotification.fromJson).toList();
    return NotificationPage(
      items: list,
      unreadCount: (data['unreadCount'] as num?)?.toInt() ?? 0,
      total: (data['total'] as num?)?.toInt() ?? list.length,
    );
  }

  static Future<void> markRead(String id) async {
    await ApiClient.patch('/api/notifications/$id/read');
  }

  static Future<void> markAllRead() async {
    await ApiClient.post('/api/notifications/read-all');
  }
}
