import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

/// Thin wrapper over Stripe's PaymentSheet.
///
/// The app is configured with the PUBLISHABLE key only (STRIPE_PUBLISHABLE_KEY
/// in .env). It never sees the secret key: every charge is created on the
/// backend, which returns a `clientSecret` that the PaymentSheet confirms here.
/// So the client can only complete a payment the server already authorized —
/// it can't invent charges or move money on its own.
class StripeService {
  static bool _initialized = false;

  static String get _publishableKey => (dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? '').trim();

  static bool get isConfigured => _publishableKey.isNotEmpty;

  /// Initialize Stripe once, at startup. Safe to call when unconfigured — it
  /// simply no-ops so the rest of the app still runs (payment actions then
  /// surface a clear "not configured" error instead of crashing).
  static Future<void> init() async {
    if (_initialized || !isConfigured) return;
    Stripe.publishableKey = _publishableKey;
    await Stripe.instance.applySettings();
    _initialized = true;
  }

  /// Present the PaymentSheet for a backend-created PaymentIntent and wait for
  /// the rider to complete or cancel it. Throws [StripeException] on
  /// cancellation or failure (callers should catch and treat as "not paid").
  static Future<void> presentPaymentSheet({
    required String clientSecret,
    String merchantDisplayName = 'RavelGo',
  }) async {
    if (!isConfigured) {
      throw Exception('Payments are not configured. Set STRIPE_PUBLISHABLE_KEY.');
    }
    await init();
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: merchantDisplayName,
      ),
    );
    await Stripe.instance.presentPaymentSheet();
  }
}
