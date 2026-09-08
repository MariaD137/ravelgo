import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/admin_notification_navigation.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// Admin notification center — backed by the real GET /api/notifications
/// feed (AA-2). Every row here was created by an actual backend event via
/// notifyAllAdmins() (see backend/src/lib/notifications.ts and its call
/// sites: a payment failure, a safety/fraud alert being raised, or a trip
/// being disputed) — nothing is fabricated client-side.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  String? _error;
  List<AdminNotification> _notifications = const [];
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await AdminApi.notifications();
      if (!mounted) return;
      setState(() {
        _notifications = page.items;
        _unreadCount = page.unreadCount;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    if (_unreadCount == 0) return;
    // Optimistic — a pull-to-refresh corrects the UI if this ever fails.
    setState(() {
      _notifications = _notifications
          .map((n) => AdminNotification(
                id: n.id,
                type: n.type,
                title: n.title,
                body: n.body,
                read: true,
                referenceType: n.referenceType,
                referenceId: n.referenceId,
                createdAt: n.createdAt,
              ))
          .toList();
      _unreadCount = 0;
    });
    try {
      await AdminApi.markAllNotificationsRead();
    } catch (_) {
      _load();
    }
  }

  Future<void> _onTapNotification(AdminNotification n) async {
    if (!n.read) {
      setState(() {
        final i = _notifications.indexWhere((x) => x.id == n.id);
        if (i != -1) {
          _notifications[i] = AdminNotification(
            id: n.id,
            type: n.type,
            title: n.title,
            body: n.body,
            read: true,
            referenceType: n.referenceType,
            referenceId: n.referenceId,
            createdAt: n.createdAt,
          );
          _unreadCount = _unreadCount > 0 ? _unreadCount - 1 : 0;
        }
      });
      AdminApi.markNotificationRead(n.id).catchError((_) {});
    }
    if (!mounted) return;
    await openAdminNotificationReference(Navigator.of(context), referenceType: n.referenceType, referenceId: n.referenceId);
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  IconData _iconFor(String type) {
    if (type.contains('PAYMENT')) return Icons.payment;
    if (type.contains('SAFETY_ALERT')) return Icons.warning_amber_rounded;
    if (type.contains('TRIP_DISPUTED')) return Icons.gavel_outlined;
    return Icons.notifications_none;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_unreadCount > 0)
            TextButton(onPressed: _markAllRead, child: const Text('Mark all read')),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 8),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_notifications.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            const Center(child: Icon(Icons.notifications_none, size: 64, color: AppColors.textMuted)),
            const SizedBox(height: 16),
            const Center(
              child: Text('No notifications yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Payment failures, safety/fraud alerts and disputed trips will appear here as they happen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _notifications.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final n = _notifications[i];
          return ListTile(
            onTap: () => _onTapNotification(n),
            leading: CircleAvatar(
              backgroundColor: n.read ? AppColors.surfaceElevated : AppColors.primary.withValues(alpha: 0.15),
              child: Icon(_iconFor(n.type), color: n.read ? AppColors.textSecondary : AppColors.primaryDark, size: 20),
            ),
            title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(n.body, style: const TextStyle(color: AppColors.textSecondary)),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_relativeTime(n.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                if (!n.read) ...[
                  const SizedBox(height: 6),
                  Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
