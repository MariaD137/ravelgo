import 'package:url_launcher/url_launcher.dart';

/// Opens a backend-issued Paystack checkout page.
///
/// Unlike the removed Stripe integration, this needs NO client-side
/// configuration at all — no publishable key, nothing set up at app
/// startup. Every charge is initialized on the backend (which holds the
/// Paystack SECRET key, never shipped to this app) and returns a one-time,
/// already-authorized `authorizationUrl`; the app just opens it. So the
/// client can only complete a payment the server already authorized — it
/// can't invent charges or move money on its own.
///
/// Opened in an in-app browser tab (Chrome Custom Tabs / SFSafariViewController
/// via url_launcher) rather than a custom WebView: Paystack's checkout page
/// can involve bank OTP / 3D-Secure steps that are safer handled by the
/// platform's own trusted browser surface than a bespoke WebView.
///
/// There is no reliable, cross-platform way to detect the user completing
/// or abandoning payment inside that external browser tab — the actual
/// outcome is only ever known once Paystack's signed webhook confirms it
/// backend-side (see billing.routes.ts), same as the PaymentSheet flow this
/// replaces already required. Callers should re-fetch the real
/// trip/booking/wallet status after this returns rather than assuming
/// success.
class PaystackService {
  /// Opens [authorizationUrl]. Throws if the browser could not be launched
  /// at all (callers should catch and treat as "payment not started").
  static Future<void> openCheckout(String authorizationUrl) async {
    final uri = Uri.parse(authorizationUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!opened) {
      throw Exception('Could not open the payment page. Please try again.');
    }
  }
}
