import 'package:flutter/material.dart';

class RideController {
  static ValueNotifier<bool> isRideActive = ValueNotifier(false);

  static void startRide() {
    isRideActive.value = true;
  }

  static void stopRide() {
    isRideActive.value = false;
  }
}