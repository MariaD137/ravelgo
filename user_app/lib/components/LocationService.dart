import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Why [LocationService.getCurrentLocation] failed — lets a caller show a
/// specific message (or decide whether to prompt for settings) instead of
/// a single generic "couldn't get your location," which is all the
/// previous swallow-everything-into-one-print implementation allowed.
enum LocationFailureReason {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  unavailable,
}

class LocationException implements Exception {
  const LocationException(this.reason, this.message);

  final LocationFailureReason reason;
  final String message;

  @override
  String toString() => message;
}

class LocationService {
  /// Throws a [LocationException] carrying a specific [LocationFailureReason]
  /// on failure, rather than swallowing every failure mode into one
  /// `print()` and returning null — callers that only need "did it work"
  /// can still just catch [LocationException] generically.
  static Future<Position> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(LocationFailureReason.serviceDisabled, 'Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationException(LocationFailureReason.permissionDenied, 'Location permission denied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        LocationFailureReason.permissionDeniedForever,
        'Location permission permanently denied.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const LocationException(LocationFailureReason.timeout, 'Getting your location took too long.');
    } catch (e) {
      debugPrint('LocationService.getCurrentLocation(): $e');
      throw LocationException(LocationFailureReason.unavailable, 'Could not determine your location.');
    }
  }
}
