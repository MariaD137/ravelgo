import 'package:ravelgo_user_app/services/api_client.dart';

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// Server-authoritative payment rules (GET /api/settings/payment). The rider
/// app uses this to disable Cash above the limit in the UI — but the backend
/// re-checks the exact same rule when the payment is actually settled
/// (POST /api/trips/:id/pay), so this is a UX convenience, never the
/// enforcement itself.
class PaymentSettings {
  final double cashPaymentLimit;
  final bool cashPaymentEnabled;
  final bool cardPaymentEnabled;
  final bool walletPaymentEnabled;

  PaymentSettings({
    required this.cashPaymentLimit,
    required this.cashPaymentEnabled,
    required this.cardPaymentEnabled,
    required this.walletPaymentEnabled,
  });

  /// Whether Cash should be offered for a given fare, mirroring the backend's
  /// isCashPaymentAllowed() — kept in sync by construction since both read
  /// the exact same limit from this response.
  bool allowsCash(double fare) => cashPaymentEnabled && fare > 0 && fare <= cashPaymentLimit;

  factory PaymentSettings.fromJson(Map<String, dynamic> j) => PaymentSettings(
        cashPaymentLimit: j['cashPaymentLimit'] == null ? 15000 : _d(j['cashPaymentLimit']),
        cashPaymentEnabled: j['cashPaymentEnabled'] != false,
        cardPaymentEnabled: j['cardPaymentEnabled'] != false,
        walletPaymentEnabled: j['walletPaymentEnabled'] != false,
      );

  /// Conservative fallback if the settings call fails — never wider than the
  /// documented default, so a network hiccup can't accidentally offer Cash
  /// above the real backend limit.
  factory PaymentSettings.fallback() => PaymentSettings(
        cashPaymentLimit: 15000,
        cashPaymentEnabled: true,
        cardPaymentEnabled: true,
        walletPaymentEnabled: true,
      );
}

class SettingsApi {
  static Future<PaymentSettings> paymentSettings() async {
    final data = await ApiClient.get('/api/settings/payment');
    return PaymentSettings.fromJson(data as Map<String, dynamic>);
  }
}
