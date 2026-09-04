import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/eats_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Restaurant menu + a simple cart. Prices and the order total are always the
/// backend's figures; this screen only proposes quantities.
class RestaurantDetailScreen extends StatefulWidget {
  final String restaurantId;
  final String name;
  const RestaurantDetailScreen({super.key, required this.restaurantId, required this.name});

  @override
  State<RestaurantDetailScreen> createState() => _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState extends State<RestaurantDetailScreen> {
  final _addressController = TextEditingController();
  final Map<String, int> _qty = {};
  Restaurant? _restaurant;
  bool _loading = true;
  String? _error;
  bool _placing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await EatsApi.restaurant(widget.restaurantId);
      if (!mounted) return;
      setState(() {
        _restaurant = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  double get _estimatedSubtotal {
    final r = _restaurant;
    if (r == null) return 0;
    var sum = 0.0;
    for (final m in r.menu) {
      sum += m.price * (_qty[m.id] ?? 0);
    }
    return sum;
  }

  int get _itemCount => _qty.values.fold(0, (a, b) => a + b);

  Future<void> _placeOrder() async {
    if (_itemCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one item.')));
      return;
    }
    if (_addressController.text.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a delivery address.')));
      return;
    }
    setState(() => _placing = true);
    try {
      final order = await EatsApi.placeOrder(
        restaurantId: widget.restaurantId,
        deliveryAddress: _addressController.text.trim(),
        quantities: _qty,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order placed — ${Currency.format(order.total)} · ${order.status}')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException && e.statusCode == 403
          ? 'Your account isn\'t set up as a rider yet.'
          : (e is ApiException ? e.message : e.toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: _body(),
      bottomNavigationBar: (_restaurant == null || _loading) ? null : _checkoutBar(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final r = _restaurant!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(r.cuisine, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(r.address, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        const SizedBox(height: 16),
        const Text('Menu', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 8),
        for (final m in r.menu) _menuRow(m),
        const SizedBox(height: 20),
        const Text('Delivery address', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _addressController,
          decoration: const InputDecoration(
            hintText: 'Where should we deliver?',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _menuRow(MenuItem m) {
    final qty = _qty[m.id] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (m.description != null && m.description!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(m.description!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
                const SizedBox(height: 2),
                Text(Currency.format(m.price),
                    style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          _stepper(m.id, qty),
        ],
      ),
    );
  }

  Widget _stepper(String id, int qty) {
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: qty == 0 ? null : () => setState(() => _qty[id] = qty - 1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$qty', style: const TextStyle(fontWeight: FontWeight.w600)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _qty[id] = qty + 1),
          icon: const Icon(Icons.add_circle_outline, color: AppColors.primaryDark),
        ),
      ],
    );
  }

  Widget _checkoutBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_itemCount item${_itemCount == 1 ? '' : 's'}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  Text('Subtotal ${Currency.format(_estimatedSubtotal)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _placing ? null : _placeOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              ),
              child: _placing
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Place order'),
            ),
          ],
        ),
      ),
    );
  }
}
