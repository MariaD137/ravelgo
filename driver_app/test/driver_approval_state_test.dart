import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/views/home/account_status_card.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';

// The driver app's view of its own approval state must come ONLY from the
// backend's Driver.status (GET /drivers/me). These tests pin down that the
// UI never fabricates "under review", and that each real backend state
// renders as itself.
void main() {
  Widget host(
    DriverProfile profile, {
    DriverProfileLoadState state = DriverProfileLoadState.ready,
    String? error,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: DriverAccountStatusCard(
          profile: profile,
          loadState: state,
          loadError: error,
          onRefresh: () async {},
          onOpenDocuments: () {},
        ),
      ),
    );
  }

  test(
    'DriverRecord parses the real status and documents, and never invents a status',
    () {
      final record = DriverRecord.fromJson({
        'id': 'drv-1',
        'status': 'PENDING_REVIEW',
        'isOnline': false,
        'rating': 5,
        'totalTrips': 0,
        'user': {'phoneNumber': '+2348000000000'},
        'documents': [
          {'id': 'd1', 'title': "Driver's License", 'status': 'APPROVED'},
          {'id': 'd2', 'title': 'Insurance', 'status': 'PENDING'},
          {
            'id': 'd3',
            'title': 'Proof of Address',
            'status': 'REJECTED',
            'rejectionReason': 'Blurry',
          },
        ],
      });
      expect(record.status, 'PENDING_REVIEW');
      expect(record.isApproved, isFalse);
      expect(record.documents.length, 3);

      final profile = DriverProfile.fromRecord(record);
      expect(profile.isPendingReview, isTrue);
      expect(profile.approvedDocumentCount, 1);
      expect(profile.pendingDocumentCount, 1);
      expect(profile.rejectedDocumentCount, 1);

      // A response with no status must not read as any review outcome.
      final missing = DriverRecord.fromJson({'id': 'drv-2'});
      expect(missing.status, '');
      expect(DriverProfile.fromRecord(missing).hasStatus, isFalse);
      // And the unloaded default profile is not "pending" either.
      expect(const DriverProfile().hasStatus, isFalse);
      expect(const DriverProfile().isPendingReview, isFalse);
    },
  );

  testWidgets(
    'an unloaded profile shows a loading state, not "Application under review"',
    (tester) async {
      await tester.pumpWidget(
        host(const DriverProfile(), state: DriverProfileLoadState.loading),
      );
      expect(find.text('Checking your account status…'), findsOneWidget);
      expect(find.text('Application under review'), findsNothing);
    },
  );

  testWidgets(
    'a failed load shows the failure with a retry, not "Application under review"',
    (tester) async {
      await tester.pumpWidget(
        host(
          const DriverProfile(),
          state: DriverProfileLoadState.error,
          error: 'Insufficient permissions',
        ),
      );
      expect(find.text("Couldn't load your account status"), findsOneWidget);
      expect(find.text('Insufficient permissions'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Application under review'), findsNothing);
    },
  );

  testWidgets(
    'PENDING_REVIEW from the backend renders as under review with the real document state',
    (tester) async {
      final profile = DriverProfile(
        status: 'PENDING_REVIEW',
        documents: [
          DriverDocument(
            id: 'd1',
            title: 'License',
            status: 'APPROVED',
            expiryDate: null,
          ),
          DriverDocument(
            id: 'd2',
            title: 'Insurance',
            status: 'REJECTED',
            expiryDate: null,
          ),
        ],
      );
      await tester.pumpWidget(host(profile));
      expect(find.text('Application under review'), findsOneWidget);
      expect(find.textContaining('1 approved · 1 rejected'), findsOneWidget);
      expect(find.text('View documents'), findsOneWidget);
    },
  );

  testWidgets('SUSPENDED renders as suspended, never as under review', (
    tester,
  ) async {
    await tester.pumpWidget(host(const DriverProfile(status: 'SUSPENDED')));
    expect(find.text('Account suspended'), findsOneWidget);
    expect(find.text('Application under review'), findsNothing);
  });

  testWidgets(
    'a quiet refresh failure keeps the last real status and says the refresh failed',
    (tester) async {
      await tester.pumpWidget(
        host(
          const DriverProfile(status: 'PENDING_REVIEW'),
          error: 'Could not reach the server.',
        ),
      );
      expect(find.text('Application under review'), findsOneWidget);
      expect(find.textContaining('Last refresh failed'), findsOneWidget);
    },
  );

  test(
    'ACTIVE is the only approved state (matches backend DriverStatus + availability gate)',
    () {
      expect(const DriverProfile(status: 'ACTIVE').isApproved, isTrue);
      expect(const DriverProfile(status: 'PENDING_REVIEW').isApproved, isFalse);
      expect(const DriverProfile(status: 'SUSPENDED').isApproved, isFalse);
      expect(
        const DriverProfile(status: 'APPROVED').isApproved,
        isFalse,
      ); // not a real backend value
    },
  );
}
