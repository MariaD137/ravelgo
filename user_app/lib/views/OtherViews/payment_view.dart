import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:ravelgo_user/services/api_client.dart';
import 'package:ravelgo_user/services/payment_service.dart';

class PaymentView extends StatefulWidget {
  const PaymentView({super.key});

  @override
  State createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentView> {
  String _selectedMethod = 'CARD';
  List<dynamic> _paymentHistory = [];
  bool _isLoading = false;
  String? _historyError;
  final Set<String> _payingIds = {};

  @override
  void initState() {
    super.initState();
    _loadPaymentHistory();
  }

  Future<void> _loadPaymentHistory() async {
    setState(() {
      _isLoading = true;
      _historyError = null;
    });
    try {
      final history = await PaymentService().getPaymentHistory();
      if (!mounted) return;
      setState(() {
        _paymentHistory = history;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _historyError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _historyError = 'Unable to load payment history.';
      });
    }
  }

  /// Presents the Stripe PaymentSheet for a trip's already-created pending
  /// CARD charge. Returning normally from PaymentService.payForTrip means
  /// Stripe accepted the confirmation — the Payment row itself only moves
  /// to SUCCEEDED once the backend's webhook processes it asynchronously,
  /// so this refreshes history afterward rather than assuming success.
  Future<void> _payNow(String tripId, String paymentId) async {
    setState(() => _payingIds.add(paymentId));
    try {
      await PaymentService().payForTrip(tripId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment submitted. This may take a moment to confirm.')),
      );
      await _loadPaymentHistory();
    } on StripeException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.error.message)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to complete payment. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _payingIds.remove(paymentId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8F8F8),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  BackButton(color: Colors.black),
                  Spacer(),
                  Text('Payment', style: TextStyle(fontSize: 20, fontWeight: FontWeight.normal, color: Colors.black)),
                  Spacer(),
                  SizedBox(width: 64),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(0.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Payment method", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _buildMethodTile('Cash', 'CASH', Icons.money),
                      _buildMethodTile('Card (Stripe)', 'CARD', Icons.credit_card),
                      _buildMethodTile('Wallet', 'WALLET', Icons.account_balance_wallet),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Payment history", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (_historyError != null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Text(_historyError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                                const SizedBox(height: 8),
                                TextButton(onPressed: _loadPaymentHistory, child: const Text('Retry')),
                              ],
                            ),
                          ),
                        )
                      else if (_paymentHistory.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text("No payment history yet", style: TextStyle(color: Colors.grey)),
                          ),
                        )
                      else
                        ...(_paymentHistory.map((payment) {
                          final paymentId = payment['id'] as String;
                          final tripId = payment['tripId'] as String? ?? payment['trip']?['id'] as String?;
                          final isPending = payment['status'] == 'PENDING' && payment['method'] == 'CARD';
                          final isPaying = _payingIds.contains(paymentId);
                          return ListTile(
                            title: Text('${payment['trip']?['pickup'] ?? 'Trip'} → ${payment['trip']?['destination'] ?? ''}'),
                            subtitle: Text('${payment['method']} - ${payment['status']}'),
                            trailing: isPending && tripId != null
                                ? SizedBox(
                                    width: 96,
                                    child: ElevatedButton(
                                      onPressed: isPaying ? null : () => _payNow(tripId, paymentId),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.amber,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                      ),
                                      child: isPaying
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Text('Pay now', style: TextStyle(fontSize: 12)),
                                    ),
                                  )
                                : Text(
                                    '\$${(payment['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                          );
                        })),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMethodTile(String label, String method, IconData icon) {
    final isSelected = _selectedMethod == method;
    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.amber : Colors.grey),
      title: Text(label),
      trailing: Radio<String>(
        value: method,
        // ignore: deprecated_member_use
        groupValue: _selectedMethod,
        activeColor: Colors.amber,
        // ignore: deprecated_member_use
        onChanged: (value) {
          if (value != null) setState(() => _selectedMethod = value);
        },
      ),
      onTap: () => setState(() => _selectedMethod = method),
    );
  }
}
