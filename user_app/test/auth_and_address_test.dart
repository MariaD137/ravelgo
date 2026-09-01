import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_user_app/Model/app_state.dart';
import 'package:ravelgo_user_app/views/Login/ForgotPassword.dart';
import 'package:ravelgo_user_app/views/Login/login.dart';
import 'package:ravelgo_user_app/views/OtherViews/AddressSearch.dart';

void main() {
  testWidgets('sign in rejects empty and malformed credentials', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Login()));

    await tester.tap(find.text('Sign in').last);
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    expect(find.byType(Login), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
    await tester.enterText(find.byType(TextFormField).at(1), '123');
    await tester.tap(find.text('Sign in').last);
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    expect(find.byType(Login), findsOneWidget);
  });

  testWidgets('forgot password validates the email before requesting a code',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));

    // Offers to send a Cognito reset code; never pre-claims one was sent.
    expect(find.text('Send code'), findsOneWidget);
    expect(find.textContaining('has been sent'), findsNothing);

    // A malformed email is rejected client-side, before any network call.
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('address search filters and saves the selection', (WidgetTester tester) async {
    RiderAppState.instance.savedAddresses.remove('Home');
    await tester.pumpWidget(const MaterialApp(home: AddressSearch(addressType: 'Home')));

    await tester.enterText(
        find.descendant(of: find.byType(Row).first, matching: find.byType(TextField)).first,
        'Ikeja');
    await tester.pump();
    expect(find.textContaining('Ikeja City Mall'), findsOneWidget);
    expect(find.textContaining('Victoria Island'), findsNothing);

    await tester.tap(find.textContaining('Ikeja City Mall'));
    await tester.pumpAndSettle();
    expect(RiderAppState.instance.savedAddresses['Home'], 'Ikeja City Mall, Alausa, Ikeja');
  });
}
