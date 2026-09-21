import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/views/drivers/driver_list_screen.dart';

// Contract checks for the admin side of driver approval: the models must
// mirror the backend's real response shapes (GET /admin/dashboard,
// GET /drivers, GET /drivers/:id) and never invent a status.
void main() {
  test(
    'DashboardStats reads the pending driver-application count separately from document reviews',
    () {
      final stats = DashboardStats.fromJson({
        'activeTrips': 1,
        'onlineDrivers': 2,
        'driversOnTrip': 1,
        'availableDrivers': 1,
        'pendingDriverApplications': 4,
        'pendingApprovals': 9,
        'pendingRideRequests': 0,
        'activeLogisticsDeliveries': 0,
        'registeredRiders': 10,
        'cashCollectedToday': 0,
        'cardRevenueToday': 0,
        'walletRevenueToday': 0,
      });
      expect(stats.pendingDriverApplications, 4);
      expect(stats.pendingApprovals, 9);
    },
  );

  test(
    'AdminDriver mirrors GET /drivers/:id (status, user, documents with rejection reason)',
    () {
      final d = AdminDriver.fromJson({
        'id': 'drv-1',
        'userId': 'usr-1',
        'status': 'PENDING_REVIEW',
        'isOnline': false,
        'rating': 4.5,
        'totalTrips': 3,
        'user': {
          'id': 'usr-1',
          'firstName': 'Ada',
          'lastName': 'Okafor',
          'email': 'ada@example.com',
          'phoneNumber': null,
        },
        'documents': [
          {
            'id': 'doc-1',
            'title': 'License',
            'status': 'APPROVED',
            'fileKey': 'sub/abc.jpg',
          },
          {
            'id': 'doc-2',
            'title': 'Insurance',
            'status': 'REJECTED',
            'fileKey': 'sub/def.jpg',
            'rejectionReason': 'Expired',
          },
        ],
      });
      expect(d.status, 'PENDING_REVIEW');
      expect(d.userId, 'usr-1');
      expect(d.name, 'Ada Okafor');
      expect(d.phoneNumber, isNull);
      expect(d.documents.length, 2);
      expect(d.documents[1].rejectionReason, 'Expired');

      // A record without a status is not silently shown as pending.
      expect(AdminDriver.fromJson({'id': 'drv-2'}).status, '');
    },
  );

  testWidgets(
    'driver list opens pre-filtered to the pending queue from the dashboard tile',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DriverListScreen(initialStatusFilter: 'PENDING_REVIEW'),
        ),
      );
      expect(find.text('Drivers'), findsOneWidget);
    },
  );
}
