import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/views/documents/my_documents_screen.dart';

// Reproduces the reported screen: "My Documents" opened while the backend
// refuses GET /documents/me. Each backend answer must render as itself, the
// stale-token case must recover without the driver doing anything, and
// "Add document" must be unavailable until the list has actually loaded.
void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://api.test.invalid');
  });

  setUp(() {
    ApiClient.resetRecoveryWindow();
    ApiClient.recoverDriverAccess = () async => false;
  });

  tearDown(() {
    ApiClient.client = http.Client();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MyDocumentsScreen()));
    await tester.pump(); // initState -> _load()
    await tester.pump(const Duration(milliseconds: 50));
  }

  bool fabEnabled(WidgetTester tester) =>
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed !=
      null;

  testWidgets(
    '403 with a token the backend refuses: explains driver access is missing, upload disabled',
    (tester) async {
      ApiClient.client = MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'Insufficient permissions'}),
          403,
        ),
      );
      await pump(tester);
      expect(
        find.textContaining("doesn't have driver access yet"),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(fabEnabled(tester), isFalse);
    },
  );

  testWidgets(
    '403 from a stale token recovers transparently once the refreshed token carries the Driver group',
    (tester) async {
      var calls = 0;
      ApiClient.client = MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response(
                jsonEncode({'error': 'Insufficient permissions'}),
                403,
              )
            : http.Response(jsonEncode([]), 200);
      });
      ApiClient.recoverDriverAccess = () async => true;
      await pump(tester);
      expect(
        find.text(
          'No documents on file yet.\nYour uploaded documents and their approval status will appear here.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('driver access'), findsNothing);
      expect(fabEnabled(tester), isTrue);
    },
  );

  testWidgets('401 is a session problem, not a driver problem', (tester) async {
    ApiClient.client = MockClient(
      (_) async =>
          http.Response(jsonEncode({'error': 'Invalid or expired token'}), 401),
    );
    await pump(tester);
    expect(find.textContaining('session has expired'), findsOneWidget);
    expect(find.textContaining('driver access'), findsNothing);
    expect(fabEnabled(tester), isFalse);
  });

  testWidgets('404 means the driver profile does not exist yet', (
    tester,
  ) async {
    ApiClient.client = MockClient(
      (_) async =>
          http.Response(jsonEncode({'error': 'Driver profile not found'}), 404),
    );
    await pump(tester);
    expect(
      find.textContaining("driver profile hasn't been created"),
      findsOneWidget,
    );
    expect(find.textContaining('driver access'), findsNothing);
  });

  testWidgets('500 is reported as a server problem', (tester) async {
    ApiClient.client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'DATABASE_ERROR',
            'message': 'Database operation failed',
          },
        }),
        500,
      ),
    );
    await pump(tester);
    expect(find.textContaining('server problem'), findsOneWidget);
    expect(find.textContaining('driver access'), findsNothing);
  });

  testWidgets(
    'a real driver with documents sees them, with their real review status',
    (tester) async {
      ApiClient.client = MockClient(
        (_) async => http.Response(
          jsonEncode([
            {'id': 'd1', 'title': "Driver's License", 'status': 'PENDING'},
            {
              'id': 'd2',
              'title': 'Insurance Certificate',
              'status': 'REJECTED',
              'rejectionReason': 'Expired',
            },
          ]),
          200,
        ),
      );
      await pump(tester);
      expect(find.text("Driver's License"), findsOneWidget);
      expect(find.text('Under review'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(fabEnabled(tester), isTrue);
    },
  );
}
