import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_driver_app/models/document_item.dart';
import 'package:ravelgo_driver_app/models/trip.dart';
import 'package:ravelgo_driver_app/models/vehicle.dart';

/// Model-level regression coverage for the real backend-shaped JSON these
/// three models now parse (GET /api/trips/mine, GET /api/documents/me,
/// GET /api/vehicles/me) — none of them have a mock/default constructor
/// anymore, so a field-name mismatch would otherwise only surface as a
/// runtime crash or silently-wrong UI, not a compile error.
void main() {
  group('Trip.fromJson', () {
    test('parses a real Trip row, including the nested rider relation', () {
      final trip = Trip.fromJson({
        'id': 'trip-1',
        'pickup': 'A',
        'destination': 'B',
        'status': 'COMPLETED',
        'estimatedFare': 2000,
        'finalFare': 2200,
        'requestedAt': '2026-08-01T10:00:00.000Z',
        'rider': {'firstName': 'Amaka', 'lastName': 'O'},
      });

      expect(trip.id, 'trip-1');
      expect(trip.status, 'COMPLETED');
      expect(trip.fare, 2200);
      expect(trip.isCancelled, isFalse);
      expect(trip.riderName, 'Amaka O');
    });

    test('falls back to estimatedFare when finalFare is null, and a generic rider name when rider is missing', () {
      final trip = Trip.fromJson({
        'id': 'trip-2',
        'pickup': 'A',
        'destination': 'B',
        'status': 'REQUESTED',
        'estimatedFare': 1000,
        'requestedAt': '2026-08-01T10:00:00.000Z',
      });

      expect(trip.fare, 1000);
      expect(trip.riderName, 'Rider');
      expect(trip.isCancelled, isFalse);
    });
  });

  group('DocumentItem.fromJson', () {
    test('maps the backend DocumentStatus enum string to the Flutter enum', () {
      final doc = DocumentItem.fromJson({
        'id': 'doc-1',
        'title': "Driver's License",
        'status': 'EXPIRING_SOON',
        'expiryDate': '2027-01-01T00:00:00.000Z',
      });

      expect(doc.status, DocumentStatus.expiringSoon);
      expect(doc.expiryDate, isNotNull);
    });

    test('defaults to notUploaded for an unrecognized/missing status', () {
      final doc = DocumentItem.fromJson({'id': 'doc-2', 'title': 'Something'});
      expect(doc.status, DocumentStatus.notUploaded);
      expect(doc.expiryDate, isNull);
    });
  });

  group('Vehicle.fromJson', () {
    test('parses a real Vehicle row', () {
      final vehicle = Vehicle.fromJson({
        'id': 'veh-1',
        'brand': 'Toyota',
        'model': 'Camry',
        'colour': 'Black',
        'plateNumber': 'LND-482-KJ',
        'year': '2021',
        'isPrimary': true,
        'listedForRental': false,
      });

      expect(vehicle.brand, 'Toyota');
      expect(vehicle.isPrimary, isTrue);
      expect(vehicle.listedForRental, isFalse);
    });
  });
}
