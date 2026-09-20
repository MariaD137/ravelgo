import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/services/driver_profile_events.dart';
import 'package:ravelgo_driver_app/views/deliveries/delivery_detail_screen.dart';
import 'package:ravelgo_driver_app/views/trips/trip_detail_screen.dart';
import 'package:ravelgo_driver_app/widgets/app_page_route.dart';

/// Opens the screen a notification refers to — shared by both the in-app
/// notification list (NotificationsScreen) and a tapped device push
/// (PushNotificationService), so a driver lands in the same place either
/// way. [referenceType]/[referenceId] are the exact fields the backend
/// attaches to every notification (backend/src/lib/notifications.ts).
///
/// No-ops for a reference type with no detail screen in this app yet, or if
/// the referenced object can no longer be resolved (deleted, reassigned, no
/// longer accessible to this account) — this never opens a dead or
/// placeholder screen.
///
/// [type] is the backend's NotificationType. A DRIVER_ACCOUNT_STATUS_CHANGED
/// notification (an admin approved/suspended/reactivated this driver) has no
/// reference to navigate to; instead it asks the shell to re-fetch the driver
/// record so the home screen reflects the real, current Driver.status. The
/// notification never sets that status itself.
Future<void> openNotificationReference(
  NavigatorState navigator, {
  required String? referenceType,
  required String? referenceId,
  String? type,
}) async {
  if (DriverProfileEvents.isAccountStatusChange(type)) {
    DriverProfileEvents.requestRefresh();
    // Land the driver back on the home screen, where the refreshed status
    // (and the go-online toggle, if approved) is shown.
    navigator.popUntil((route) => route.isFirst);
    return;
  }
  if (referenceId == null) return;

  if (referenceType == 'TRIP') {
    try {
      final trip = await DriverApi.tripById(referenceId);
      navigator.push(AppPageRoute(builder: (_) => TripDetailScreen(trip: trip)));
    } catch (_) {
      // Trip may no longer be visible to this account, or the fetch failed.
    }
  } else if (referenceType == 'COURIER_REQUEST') {
    navigator.push(AppPageRoute(builder: (_) => DeliveryDetailScreen(deliveryId: referenceId)));
  }
  // Other reference types have no dedicated detail screen in this app — the
  // notification is still shown/marked read, it just doesn't navigate
  // anywhere further.
}
