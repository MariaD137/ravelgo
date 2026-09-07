import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/services/trips_api.dart';
import 'package:ravelgo_user_app/views/Delivery/DeliveryTrackingScreen.dart';
import 'package:ravelgo_user_app/views/Rentals/RentalBookingDetailScreen.dart';
import 'package:ravelgo_user_app/views/RideView/RideDetailsView.dart';
import 'package:ravelgo_user_app/views/RideView/RidesView.dart';

/// Opens the screen a notification refers to — shared by both the in-app
/// notification list (NotificationsScreen) and a tapped device push
/// (PushNotificationService), so a customer lands in the same place either
/// way. [referenceType]/[referenceId] are the exact fields the backend
/// attaches to every notification (backend/src/lib/notifications.ts).
///
/// No-ops for a reference type with no detail screen in this app yet, or if
/// the referenced object can no longer be resolved (deleted, cancelled, no
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
      final trip = await TripsApi.byId(referenceId);
      navigator.push(MaterialPageRoute(builder: (_) => RideDetailsScreen(ride: Ride.fromTrip(trip))));
    } catch (_) {
      // Trip may no longer be visible to this account, or the fetch failed.
    }
  } else if (referenceType == 'COURIER_REQUEST') {
    navigator.push(MaterialPageRoute(builder: (_) => DeliveryTrackingScreen(deliveryId: referenceId)));
  } else if (referenceType == 'RENTAL_BOOKING') {
    navigator.push(MaterialPageRoute(builder: (_) => RentalBookingDetailScreen(bookingId: referenceId)));
  }
  // Other reference types (e.g. PAYMENT, when not for a trip/booking) have
  // no dedicated detail screen in this app — the notification is still
  // shown/marked read, it just doesn't navigate anywhere further.
}
