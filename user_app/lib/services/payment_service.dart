import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:ravelgo_user/services/api_client.dart';

class PaymentService {
  static final PaymentService _instance = PaymentService._();
  factory PaymentService() => _instance;
  PaymentService._();

  final _api = ApiClient();

  /// The clientSecret for a trip's already-created, still-pending CARD
  /// charge (see backend/src/routes/payments.routes.ts:
  /// GET /trips/:id/payment-secret). The charge itself is created by the
  /// driver/admin via POST /trips/:id/charge — a rider can never call that
  /// endpoint directly, so this is the only payment-related call this app
  /// makes before presenting the Stripe sheet.
  Future<Map<String, dynamic>> getPaymentSecret(String tripId) async {
    final response = await _api.get('/trips/$tripId/payment-secret');
    return Map<String, dynamic>.from(response);
  }

  Future<void> presentPaymentSheet(String clientSecret) async {
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'RavelGo',
        style: ThemeMode.system,
      ),
    );
    await Stripe.instance.presentPaymentSheet();
  }

  /// Fetches the pending charge's clientSecret and presents the Stripe
  /// PaymentSheet for it. Final settlement (SUCCEEDED/FAILED) happens
  /// asynchronously via the Stripe webhook once the sheet confirms the
  /// PaymentIntent — a caller should treat this method returning normally
  /// as "submitted to Stripe", not as proof the charge has settled, and
  /// re-check payment status (e.g. via getPaymentHistory) rather than
  /// assuming success. Throws [ApiException] if the secret can't be
  /// fetched (no pending charge, not this rider's trip, network/backend
  /// error) and [StripeException] if the sheet itself fails or the rider
  /// dismisses it — callers should catch both.
  Future<void> payForTrip(String tripId) async {
    final secret = await getPaymentSecret(tripId);
    final clientSecret = secret['clientSecret'] as String?;
    if (clientSecret == null) {
      throw ApiException(0, 'No payment is available for this trip yet.');
    }
    await presentPaymentSheet(clientSecret);
  }

  Future<Map<String, dynamic>> getReceipt(String paymentId) async {
    final response = await _api.get('/payments/$paymentId/receipt');
    return Map<String, dynamic>.from(response);
  }

  Future<List<dynamic>> getPaymentHistory({int page = 1, int pageSize = 10}) async {
    final response = await _api.get('/payments/mine', queryParams: {
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    });
    return response['data'] as List<dynamic>;
  }
}
