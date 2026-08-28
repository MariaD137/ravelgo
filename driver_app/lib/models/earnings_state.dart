import 'package:flutter/foundation.dart';

/// LOCAL STATE ONLY: in-memory earnings/payout state for the driver app.
/// Balances and history are demo data; a cash-out request is captured
/// locally with status "Pending" and is NEVER claimed to have transferred
/// money - executing transfers is the payments-backend integration point.
class DriverEarningsState extends ChangeNotifier {
  DriverEarningsState._();
  static final DriverEarningsState instance = DriverEarningsState._();

  double availableBalance = 122900;

  final List<Payout> payouts = [
    Payout(amount: 85000, date: DateTime.now().subtract(const Duration(days: 9)), status: PayoutStatus.paid),
    Payout(amount: 64200, date: DateTime.now().subtract(const Duration(days: 16)), status: PayoutStatus.paid),
    Payout(amount: 91750, date: DateTime.now().subtract(const Duration(days: 23)), status: PayoutStatus.paid),
  ];

  /// Records a cash-out request locally (status: pending).
  /// Integration point: submit to the payments service here.
  Payout requestCashOut(double amount) {
    final payout = Payout(amount: amount, date: DateTime.now(), status: PayoutStatus.pending);
    payouts.insert(0, payout);
    availableBalance -= amount;
    notifyListeners();
    return payout;
  }
}

enum PayoutStatus { pending, paid, failed }

extension PayoutStatusLabel on PayoutStatus {
  String get label {
    switch (this) {
      case PayoutStatus.pending:
        return 'Pending';
      case PayoutStatus.paid:
        return 'Paid';
      case PayoutStatus.failed:
        return 'Failed';
    }
  }
}

class Payout {
  final double amount;
  final DateTime date;
  final PayoutStatus status;

  Payout({required this.amount, required this.date, required this.status});
}
