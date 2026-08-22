import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_driver_app/models/driver_operational_state.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';

void main() {
  // DriverSession is a singleton (DriverSession.instance) shared across the
  // whole app on purpose (see its own doc comment) — reset it to a known
  // state before each test so tests don't leak state into one another.
  setUp(() {
    DriverSession.instance.goOffline();
  });

  group('DriverOperationalState', () {
    test('offline and available are not busy', () {
      expect(DriverOperationalState.offline.isBusy, isFalse);
      expect(DriverOperationalState.available.isBusy, isFalse);
    });

    test('onRide, onCourier, onRental are all busy', () {
      expect(DriverOperationalState.onRide.isBusy, isTrue);
      expect(DriverOperationalState.onCourier.isBusy, isTrue);
      expect(DriverOperationalState.onRental.isBusy, isTrue);
    });
  });

  group('DriverSession', () {
    test('starts offline with no active assignment', () {
      expect(DriverSession.instance.state, DriverOperationalState.offline);
      expect(DriverSession.instance.activeAssignmentId, isNull);
    });

    test('goAvailable/goOffline toggle between available and offline', () {
      DriverSession.instance.goAvailable();
      expect(DriverSession.instance.state, DriverOperationalState.available);

      DriverSession.instance.goOffline();
      expect(DriverSession.instance.state, DriverOperationalState.offline);
    });

    test('markBusy sets state and assignment id, and notifies listeners', () {
      var notified = 0;
      DriverSession.instance.addListener(() => notified++);

      DriverSession.instance.markBusy(DriverOperationalState.onCourier, 'courier-123');

      expect(DriverSession.instance.state, DriverOperationalState.onCourier);
      expect(DriverSession.instance.activeAssignmentId, 'courier-123');
      expect(notified, greaterThan(0));
    });

    test('reconcile(busy: false) returns to available when not offline', () {
      DriverSession.instance.goAvailable();
      DriverSession.instance.markBusy(DriverOperationalState.onRide, 'trip-1');

      DriverSession.instance.reconcile(busy: false);

      expect(DriverSession.instance.state, DriverOperationalState.available);
      expect(DriverSession.instance.activeAssignmentId, isNull);
    });

    test('reconcile(busy: false) stays offline if it was offline (never auto-goes-online)', () {
      DriverSession.instance.goOffline();

      DriverSession.instance.reconcile(busy: false);

      expect(DriverSession.instance.state, DriverOperationalState.offline);
    });

    test('reconcile(busy: true) maps RIDE/COURIER/RENTAL to the matching busy state', () {
      DriverSession.instance.reconcile(busy: true, assignmentType: 'RIDE', assignmentId: 'trip-9');
      expect(DriverSession.instance.state, DriverOperationalState.onRide);
      expect(DriverSession.instance.activeAssignmentId, 'trip-9');

      DriverSession.instance.reconcile(busy: true, assignmentType: 'COURIER', assignmentId: 'courier-9');
      expect(DriverSession.instance.state, DriverOperationalState.onCourier);

      DriverSession.instance.reconcile(busy: true, assignmentType: 'RENTAL', assignmentId: 'rental-9');
      expect(DriverSession.instance.state, DriverOperationalState.onRental);
    });
  });
}
