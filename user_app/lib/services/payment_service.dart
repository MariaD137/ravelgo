import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:ravelgo_user/services/api_client.dart';

class PaymentService {
  static final PaymentService _instance = PaymentService._();
  factory PaymentService() => _instance;
  PaymentService._();

  final _api = ApiClient();

  Future<Map<String, dynamic>> chargeTrip(String tripId, {String method = 'CARD'}) async {
    final response = await _api.post('/trips/$tripId/charge', body: {'method': method});
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

  Future<Map<String, dynamic>> payForTrip(String tripId) async {
    final chargeResult = await chargeTrip(tripId, method: 'CARD');
    final clientSecret = chargeResult['clientSecret'] as String?;
    if (clientSecret == null) {
      throw Exception('No client secret returned from server');
    }
    await presentPaymentSheet(clientSecret);
    return chargeResult;
  }

  Future<Map<String, dynamic>> payWithCash(String tripId) async {
    return chargeTrip(tripId, method: 'CASH');
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
