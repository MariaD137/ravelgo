import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_admin/services/paging.dart';
import 'package:ravelgo_admin/widgets/pagination_bar.dart';

// A-1: the Admin App pages through every list with the backend's shared
// pagination contract. These pin the model's reading of that contract and
// the bar's navigation rules.
void main() {
  test(
    'PagedResult reads the backend contract, including the additive metadata',
    () {
      final r = PagedResult.fromJson({
        'data': [
          {'id': 'a'},
          {'id': 'b'},
        ],
        'page': 2,
        'pageSize': 2,
        'total': 5,
        'totalPages': 3,
        'hasNext': true,
      }, (j) => j['id'] as String);
      expect(r.items, ['a', 'b']);
      expect(r.page, 2);
      expect(r.total, 5);
      expect(r.totalPages, 3);
      expect(r.hasNext, isTrue);
      expect(r.hasPrev, isTrue);
      expect(r.isPastEnd, isFalse);
    },
  );

  test(
    'PagedResult derives totalPages/hasNext when a response omits them, and flags a page past the end',
    () {
      final r = PagedResult.fromJson({
        'data': [],
        'page': 4,
        'pageSize': 50,
        'total': 120,
      }, (j) => j);
      expect(r.totalPages, 3);
      expect(r.hasNext, isFalse);
      expect(
        r.isPastEnd,
        isTrue,
        reason: 'empty page 4 of 3 means the screen must snap back',
      );

      final empty = PagedResult.fromJson({
        'data': [],
        'page': 1,
        'pageSize': 50,
        'total': 0,
      }, (j) => j);
      expect(empty.totalPages, 1);
      expect(
        empty.isPastEnd,
        isFalse,
        reason: 'an empty list is not "past the end"',
      );
    },
  );

  test('pagedQuery encodes page, size and only the filters that are set', () {
    expect(pagedQuery(2), 'page=2&pageSize=$kAdminPageSize');
    expect(
      pagedQuery(
        1,
        filters: {'status': 'MATCHED,IN_PROGRESS', 'type': null, 'q': ''},
      ),
      'page=1&pageSize=$kAdminPageSize&status=MATCHED%2CIN_PROGRESS',
    );
  });

  testWidgets(
    'PaginationBar hides on a single page and navigates within bounds',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaginationBar(
              page: 1,
              totalPages: 1,
              total: 0,
              onPageChanged: (_) {},
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.chevron_right), findsNothing);

      int? requested;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaginationBar(
              page: 1,
              totalPages: 3,
              total: 120,
              itemLabel: 'riders',
              onPageChanged: (p) => requested = p,
            ),
          ),
        ),
      );
      expect(find.text('Page 1 of 3  ·  120 riders'), findsOneWidget);
      // Previous is disabled on the first page.
      final prev = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left),
      );
      expect(prev.onPressed, isNull);
      await tester.tap(find.byIcon(Icons.chevron_right));
      expect(requested, 2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaginationBar(
              page: 3,
              totalPages: 3,
              total: 120,
              onPageChanged: (p) => requested = p,
            ),
          ),
        ),
      );
      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(
        next.onPressed,
        isNull,
        reason: 'next is disabled on the last page',
      );
      await tester.tap(find.byIcon(Icons.chevron_left));
      expect(requested, 2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaginationBar(
              page: 2,
              totalPages: 3,
              total: 120,
              busy: true,
              onPageChanged: (p) => requested = 99,
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right),
            )
            .onPressed,
        isNull,
        reason: 'no page change while a page is loading',
      );
    },
  );
}
