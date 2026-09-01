import 'package:ravelgo_user_app/services/api_client.dart';

/// Rider-initiated payment for the rider's own completed trip (P0 #1). Both
/// methods hit POST /api/trips/:id/pay, which charges the server-authoritative
/// fare and guarantees exactly one payment per trip — the client never asserts
/// an amount and cannot double-charge.
class PaymentsApi {
  /// Pay a completed trip by CARD. The backend creates a Stripe PaymentIntent
  /// and returns its clientSecret, which the app confirms via the PaymentSheet.
  static Future<String> payTripWithCard(String tripId) async {
    final data = await ApiClient.post('/api/trips/$tripId/pay', {'method': 'CARD'});
    final m = data as Map<String, dynamic>;
    final secret = m['clientSecret'];
    if (secret == null || '$secret'.isEmpty) {
      throw Exception('Card payment could not be started.');
    }
    return '$secret';
  }

  /// Pay a completed trip from the rider's RavelGo wallet balance. Settles
  /// immediately on the backend (atomic debit); throws on insufficient funds
  /// (402) or if already charged (409).
  static Future<void> payTripWithWallet(String tripId) async {
    await ApiClient.post('/api/trips/$tripId/pay', {'method': 'WALLET'});
  }
}
