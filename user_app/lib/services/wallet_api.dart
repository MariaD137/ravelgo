import 'package:ravelgo_user_app/services/api_client.dart';

class WalletBalance {
  final double balance;
  final String currency;
  WalletBalance(this.balance, this.currency);
}

class WalletTransaction {
  final String id;
  final String type;
  final String status;
  final double amount;
  final String? tripId;
  final DateTime createdAt;

  WalletTransaction({
    required this.id,
    required this.type,
    required this.status,
    required this.amount,
    required this.tripId,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> j) => WalletTransaction(
        id: '${j['id']}',
        type: '${j['type'] ?? ''}',
        status: '${j['status'] ?? ''}',
        amount: (j['amount'] is num) ? (j['amount'] as num).toDouble() : double.tryParse('${j['amount']}') ?? 0,
        tripId: j['tripId']?.toString(),
        createdAt: DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? DateTime.now(),
      );
}

class WalletApi {
  /// The signed-in user's wallet balance and currency.
  static Future<WalletBalance> me() async {
    final data = await ApiClient.get('/api/wallet/me');
    final m = data as Map<String, dynamic>;
    return WalletBalance(
      (m['balance'] is num) ? (m['balance'] as num).toDouble() : double.tryParse('${m['balance']}') ?? 0,
      '${m['currency'] ?? 'USD'}',
    );
  }

  /// The signed-in user's recent wallet transactions, newest first.
  static Future<List<WalletTransaction>> transactions() async {
    final data = await ApiClient.get('/api/wallet/transactions');
    final list = data as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(WalletTransaction.fromJson).toList();
  }
}
