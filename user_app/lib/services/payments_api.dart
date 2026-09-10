import 'package:ravelgo_user_app/services/api_client.dart';

/// Rider-initiated payment for the rider's own completed trip (P0 #1). Both
/// methods hit POST /api/trips/:id/pay, which charges the server-authoritative
/// fare and guarantees exactly one payment per trip — the client never asserts
/// an amount and cannot double-charge.
class PaymentsApi {
  /// Pay a completed trip by CARD. The backend initializes a Paystack
  /// transaction and returns its authorizationUrl, which the app opens for
  /// the rider to pay.
  static Future<String> payTripWithCard(String tripId) async {
    final data = await ApiClient.post('/api/trips/$tripId/pay', {'method': 'CARD'});
    final m = data as Map<String, dynamic>;
    final url = m['authorizationUrl'];
    if (url == null || '$url'.isEmpty) {
      throw Exception('Card payment could not be started.');
    }
    return '$url';
  }

  /// Pay a completed trip from the rider's RavelGo wallet balance. Settles
  /// immediately on the backend (atomic debit); throws on insufficient funds
  /// (402) or if already charged (409).
  static Future<void> payTripWithWallet(String tripId) async {
    await ApiClient.post('/api/trips/$tripId/pay', {'method': 'WALLET'});
  }

  /// Pay a completed trip in cash, handed directly to the driver. Settles
  /// immediately on the backend — but only below the configured cash limit
  /// (default ₦15,000): the UI should already hide this option above the
  /// limit (see SettingsApi.paymentSettings), and the backend rejects it with
  /// a 400 regardless of what the client sends.
  static Future<void> payTripWithCash(String tripId) async {
    await ApiClient.post('/api/trips/$tripId/pay', {'method': 'CASH'});
  }
}
