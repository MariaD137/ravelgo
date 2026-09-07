import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// Driver subscription plans (GET /api/subscription-plans).
class DriverSubscriptionsScreen extends StatefulWidget {
  const DriverSubscriptionsScreen({super.key});

  @override
  State<DriverSubscriptionsScreen> createState() => _DriverSubscriptionsScreenState();
}

class _DriverSubscriptionsScreenState extends State<DriverSubscriptionsScreen> {
  bool _loading = true;
  String? _error;
  List<SubscriptionPlan> _plans = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plans = await AdminApi.subscriptionPlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403 ? 'Sign in as an admin to view plans.' : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _createPlan() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final priceController = TextEditingController();

    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New subscription plan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
              TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description')),
              TextField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Price per month (₦)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (create != true || !mounted) return;

    final price = double.tryParse(priceController.text.trim());
    if (nameController.text.trim().isEmpty || descController.text.trim().isEmpty || price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a name, description and a valid price')));
      return;
    }

    try {
      await AdminApi.createSubscriptionPlan(
        name: nameController.text.trim(),
        description: descController.text.trim(),
        priceMonthly: price,
      );
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan created')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Driver Subscriptions"),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _createPlan)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null ? _err() : _list()),
    );
  }

  Widget _err() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _list() {
    if (_plans.isEmpty) {
      return const Center(child: Text("No subscription plans configured.", style: TextStyle(color: AppColors.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _plans.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final p = _plans[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                    AppComponents.badge(p.active ? "Active" : "Inactive",
                        color: p.active ? AppColors.success : AppColors.textMuted),
                  ],
                ),
                const SizedBox(height: 4),
                Text(p.description, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Text("₦${p.priceMonthly.toStringAsFixed(0)} / month",
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          );
        },
      ),
    );
  }
}
