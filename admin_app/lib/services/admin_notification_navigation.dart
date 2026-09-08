import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/views/safety/emergency_alerts_screen.dart';
import 'package:ravelgo_admin/views/trips/trip_admin_detail_screen.dart';

/// Opens the screen an admin notification refers to (AA-2). [referenceType]/
/// [referenceId] are the exact fields notifyAllAdmins() (backend
/// lib/notifications.ts) attaches to every admin notification.
///
/// No-ops for a reference type with no admin detail screen yet, or if the
/// referenced object can no longer be resolved — this never opens a dead or
/// placeholder screen.
Future<void> openAdminNotificationReference(
  NavigatorState navigator, {
  required String? referenceType,
  required String? referenceId,
}) async {
  if (referenceId == null) return;

  if (referenceType == 'TRIP') {
    try {
      final trip = await AdminApi.trip(referenceId);
      navigator.push(MaterialPageRoute(builder: (_) => TripAdminDetailScreen(trip: trip)));
    } catch (_) {
      // Trip may have been removed or is no longer resolvable.
    }
  } else if (referenceType == 'EMERGENCY_ALERT') {
    // No per-alert detail screen exists yet — the alerts list itself already
    // surfaces status and the acknowledge/resolve actions for every open
    // alert, so this opens straight to it.
    navigator.push(MaterialPageRoute(builder: (_) => const EmergencyAlertsScreen()));
  }
  // RENTAL_BOOKING notifications (a rental's card payment failing) have no
  // dedicated admin detail screen yet — admin has no rental-booking view at
  // all, only the rental-listing review screen AA-1 built. The notification
  // is still shown and can be marked read; it just doesn't navigate further.
}
