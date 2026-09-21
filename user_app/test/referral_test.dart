import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/referral_api.dart';
import 'package:ravelgo_user_app/services/session_guard.dart';
import 'package:ravelgo_user_app/views/User/invite_a_friend.dart';

/// The invite screen has twice shipped invented content — a stock reward, a
/// hardcoded code, then a share with no code in it at all. These tests pin
/// down that everything on screen comes from the backend, and that the
/// screen says nothing about a reward while the programme is off.
void main() {
  Map<String, dynamic> summary({
    bool enabled = true,
    double reward = 1000,
    double refereeReward = 0,
    int qualifyingTrips = 1,
    int pending = 0,
    int rewarded = 0,
    double earned = 0,
    String? referredByCode,
    bool canClaim = false,
    String code = 'ABCD2345',
  }) =>
      {
        'code': code,
        'program': {
          'enabled': enabled,
          'rewardAmount': reward,
          'refereeRewardAmount': refereeReward,
          'qualifyingTrips': qualifyingTrips,
        },
        'pending': pending,
        'rewarded': rewarded,
        'totalEarned': earned,
        'referredByCode': referredByCode,
        'canClaim': canClaim,
      };

  setUp(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://api.test.ravelgo');
    SessionGuard.reset();
    SessionGuard.refreshSession = () async => false;
    SessionGuard.clearSession = () async {};
    SessionGuard.hasSession = () => false;
  });

  tearDown(() {
    SessionGuard.reset();
    ApiClient.client = http.Client();
  });

  void serve(Map<String, dynamic> body, {int status = 200}) {
    ApiClient.client = MockClient((_) async => http.Response(jsonEncode(body), status));
  }

  testWidgets('the rider sees their real code and the real programme terms',
      (tester) async {
    serve(summary(code: 'RAVEL234', reward: 2500, qualifyingTrips: 3, pending: 2, rewarded: 1, earned: 2500));

    await tester.pumpWidget(const MaterialApp(home: InviteFriendsView()));
    await tester.pumpAndSettle();

    expect(find.text('RAVEL234'), findsOneWidget);
    // The offer is described in the configured amount and trip count.
    expect(find.textContaining('₦2,500'), findsWidgets);
    expect(find.textContaining('their first 3 rides'), findsOneWidget);
    // Real counts, not decoration.
    expect(find.text('3'), findsOneWidget, reason: 'invited = pending + rewarded');
    expect(find.text('Invited'), findsOneWidget);
    expect(find.text('Qualified'), findsOneWidget);
  });

  testWidgets('a disabled programme promises no reward at all', (tester) async {
    serve(summary(enabled: false, reward: 5000));

    await tester.pumpWidget(const MaterialApp(home: InviteFriendsView()));
    await tester.pumpAndSettle();

    expect(find.textContaining('no invite reward running'), findsOneWidget);
    expect(find.textContaining('₦5,000'), findsNothing,
        reason: 'a switched-off programme must not advertise a reward');
    expect(find.text('Invited'), findsNothing);
    // The code is still shown — sharing the app still works.
    expect(find.text('ABCD2345'), findsOneWidget);
  });

  testWidgets('a rider who can still claim is offered the entry point',
      (tester) async {
    serve(summary(canClaim: true));

    await tester.pumpWidget(const MaterialApp(home: InviteFriendsView()));
    await tester.pumpAndSettle();

    expect(find.text('Enter invite code'), findsOneWidget);
    // The card sits below the fold on a test-sized screen.
    await tester.ensureVisible(find.text('Enter invite code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter invite code'));
    await tester.pumpAndSettle();

    // Submitting an empty code is refused client-side before any request.
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the code your friend gave you'), findsOneWidget);
  });

  testWidgets('a rider who already joined with a code sees that, not the form',
      (tester) async {
    serve(summary(canClaim: false, referredByCode: 'FRIEND77'));

    await tester.pumpWidget(const MaterialApp(home: InviteFriendsView()));
    await tester.pumpAndSettle();

    expect(find.textContaining('FRIEND77'), findsOneWidget);
    expect(find.text('Enter invite code'), findsNothing);
  });

  testWidgets('a failed load explains itself and offers a retry', (tester) async {
    ApiClient.client = MockClient((req) async {
      throw http.ClientException('Failed to fetch', req.url);
    });

    await tester.pumpWidget(const MaterialApp(home: InviteFriendsView()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Can\'t reach RavelGo'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // No invented code is shown when we could not load one.
    expect(find.text('ABCD2345'), findsNothing);
  });

  test('ReferralSummary parses the backend payload, including absent fields', () {
    final parsed = ReferralSummary.fromJson(summary(
      code: 'ZZZZ2345',
      enabled: true,
      reward: 1500,
      refereeReward: 500,
      qualifyingTrips: 2,
      pending: 4,
      rewarded: 3,
      earned: 4500,
      referredByCode: 'OTHER123',
      canClaim: false,
    ));

    expect(parsed.code, 'ZZZZ2345');
    expect(parsed.program.rewardAmount, 1500);
    expect(parsed.program.refereeRewardAmount, 500);
    expect(parsed.program.qualifyingTrips, 2);
    expect(parsed.pending, 4);
    expect(parsed.rewarded, 3);
    expect(parsed.totalEarned, 4500);
    expect(parsed.referredByCode, 'OTHER123');
    expect(parsed.canClaim, isFalse);

    // A payload missing the programme block degrades to "off", never to a
    // guessed reward.
    final bare = ReferralSummary.fromJson({'code': 'AAAA2345'});
    expect(bare.program.enabled, isFalse);
    expect(bare.program.rewardAmount, 0);
    expect(bare.program.qualifyingTrips, 1);
    expect(bare.canClaim, isFalse);
  });
}
