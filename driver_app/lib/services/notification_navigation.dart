import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/views/deliveries/delivery_detail_screen.dart';
import 'package:ravelgo_driver_app/views/trips/trip_detail_screen.dart';

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
Future<void> openNotificationReference(
  NavigatorState navigator, {
  required String? referenceType,
  required String? referenceId,
}) async {
  if (referenceId == null) return;

  if (referenceType == 'TRIP') {
    try {
      final trip = await DriverApi.tripById(referenceId);
      navigator.push(MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip)));
    } catch (_) {
      // Trip may no longer be visible to this account, or the fetch failed.
    }
  } else if (referenceType == 'COURIER_REQUEST') {
    navigator.push(MaterialPageRoute(builder: (_) => DeliveryDetailScreen(deliveryId: referenceId)));
  }
  // Other reference types have no dedicated detail screen in this app — the
  // notification is still shown/marked read, it just doesn't navigate
  // anywhere further.
}
