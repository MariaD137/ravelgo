import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_profile_events.dart';
import 'package:ravelgo_driver_app/services/notification_navigation.dart';
import 'package:ravelgo_driver_app/services/notifications_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/widgets/empty_state.dart';
import 'package:ravelgo_driver_app/widgets/shimmer.dart';

/// Driver notification center — backed by the real GET /api/notifications
/// feed. Every row here was created by an actual backend event (see
/// backend/src/lib/notifications.ts and its call sites); nothing is
/// fabricated client-side, and an empty result renders an honest empty
/// state rather than placeholder content.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  String? _error;
  List<AppNotification> _notifications = const [];
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
      final page = await NotificationsApi.mine();
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
    // Optimistic — this is a low-stakes toggle and the pull-to-refresh below
    // will correct the UI if the request ever actually fails.
    setState(() {
      _notifications = _notifications
          .map((n) => AppNotification(
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
      await NotificationsApi.markAllRead();
    } catch (_) {
      _load();
    }
  }

  Future<void> _onTapNotification(AppNotification n) async {
    if (!n.read) {
      setState(() {
        final i = _notifications.indexWhere((x) => x.id == n.id);
        if (i != -1) {
          _notifications[i] = AppNotification(
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
      NotificationsApi.markRead(n.id).catchError((_) {});
    }
    if (!mounted) return;
    await openNotificationReference(
      Navigator.of(context),
      referenceType: n.referenceType,
      referenceId: n.referenceId,
      type: n.type,
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  IconData _iconFor(String type) {
    if (type.startsWith('RIDE_')) return Icons.directions_car;
    if (type.startsWith('DELIVERY_')) return Icons.local_shipping_outlined;
    if (type.startsWith('PAYMENT_') || type.startsWith('PAYOUT_')) return Icons.payments_outlined;
    if (DriverProfileEvents.isAccountStatusChange(type)) return Icons.verified_user_outlined;
    return Icons.notifications_none;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    return AsyncBody(
      stateKey: _loading ? "loading" : (_error != null ? "error" : "data:${_notifications.length}"),
      child: _loading
          ? const ShimmerList()
          : _error != null
              ? EmptyState(icon: Icons.cloud_off, title: "Couldn't load notifications", subtitle: _error!, onRetry: _load)
              : _notifications.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _load,
                      child: const EmptyState(
                        icon: Icons.notifications_none,
                        title: "No notifications yet",
                        subtitle: "Ride requests, delivery updates and payout updates will appear here as they happen.",
                      ),
                    )
                  : _notificationList(),
    );
  }

  Widget _notificationList() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _notifications.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
        itemBuilder: (context, i) {
          final n = _notifications[i];
          return ListTile(
            onTap: () => _onTapNotification(n),
            leading: CircleAvatar(
              backgroundColor: n.read ? AppColors.surfaceElevated : AppColors.primary.withValues(alpha: 0.15),
              child: Icon(_iconFor(n.type), color: n.read ? AppColors.textSecondary : AppColors.primaryDark, size: 20),
            ),
            title: Text(
              n.title,
              style: TextStyle(fontWeight: n.read ? FontWeight.w500 : FontWeight.w700),
            ),
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
