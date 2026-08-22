import 'api_client.dart';

/// Admin's driver-payout API surface — no Stripe integration exists yet, so
/// this only talks to the backend's own Payout ledger (services/payouts.ts);
/// it does not invent a payment-processor flow. Never imports rider_api.dart
/// or driver_api.dart.
class PayoutApi {
  PayoutApi(this._client);

  final ApiClient _client;

  /// [period] must be "YYYY-MM". Returns the calculated amount without
  /// creating a Payout row.
  Future<Map<String, dynamic>> calculate({required String driverId, required String period}) async {
    return await _client.post('/api/payouts/calculate', body: {'driverId': driverId, 'period': period})
        as Map<String, dynamic>;
  }

  /// Creates a PENDING payout. Pass [amount] to override the calculated
  /// figure; otherwise the backend calculates it from the period's trips.
  Future<Map<String, dynamic>> create({required String driverId, required String period, double? amount}) async {
    return await _client.post(
          '/api/payouts/create',
          body: {'driverId': driverId, 'period': period, if (amount != null) 'amount': amount},
        )
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> process(String payoutId) async {
    return await _client.post('/api/payouts/$payoutId/process') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> complete(String payoutId, {String? transactionId}) async {
    return await _client.post(
          '/api/payouts/$payoutId/complete',
          body: {if (transactionId != null) 'transactionId': transactionId},
        )
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fail(String payoutId, {required String failureReason}) async {
    return await _client.post('/api/payouts/$payoutId/fail', body: {'failureReason': failureReason})
        as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> list({int page = 1, int pageSize = 20, String? status, String? driverId}) async {
    final res = await _client.get(
          '/api/payouts',
          query: {
            'page': page,
            'pageSize': pageSize,
            if (status != null) 'status': status,
            if (driverId != null) 'driverId': driverId,
          },
        )
        as Map<String, dynamic>;
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }
}
