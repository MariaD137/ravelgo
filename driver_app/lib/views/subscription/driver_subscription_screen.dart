import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/config/currency.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';

/// Real subscription plans (GET /api/subscription-plans, Admin-published —
/// this screen used to show three entirely invented weekly/monthly/quarterly
/// tiers with fabricated perks and a "Subscribe" button that did nothing but
/// close the screen) and this driver's real status
/// (GET/POST/DELETE /api/drivers/me/subscription).
///
/// Known gap, not hidden from the driver: subscribing does not currently
/// collect any payment, and being subscribed has no effect yet on the
/// commission a driver is actually charged (see subscriptions.routes.ts) —
/// said plainly in the banner below rather than implying a discount that
/// isn't real.
class DriverSubscriptionScreen extends StatefulWidget {
  const DriverSubscriptionScreen({super.key});

  @override
  State<DriverSubscriptionScreen> createState() => _DriverSubscriptionScreenState();
}

class _DriverSubscriptionScreenState extends State<DriverSubscriptionScreen> {
  bool _loading = true;
  String? _error;
  List<SubscriptionPlan> _plans = const [];
  DriverSubscriptionStatus? _current;
  String? _selectedPlanId;
  bool _acting = false;

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
      final results = await Future.wait([DriverApi.subscriptionPlans(), DriverApi.mySubscription()]);
      if (!mounted) return;
      final plans = results[0] as List<SubscriptionPlan>;
      final current = results[1] as DriverSubscriptionStatus?;
      setState(() {
        _plans = plans;
        _current = current;
        _selectedPlanId = current?.status == 'ACTIVE' ? current!.plan.id : (plans.isNotEmpty ? plans.first.id : null);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Could not load subscription plans.';
        _loading = false;
      });
    }
  }

  bool get _isActive => _current?.status == 'ACTIVE';

  Future<void> _subscribe() async {
    final planId = _selectedPlanId;
    if (planId == null || _acting) return;
    setState(() => _acting = true);
    try {
      final updated = await DriverApi.subscribe(planId);
      if (!mounted) return;
      setState(() => _current = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subscribed.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Could not subscribe.')));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _cancel() async {
    if (_acting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel subscription?'),
        content: const Text('You can resubscribe at any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel subscription')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _acting = true);
    try {
      await DriverApi.cancelSubscription();
      if (!mounted) return;
      setState(() => _current = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subscription cancelled.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Could not cancel.')));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Subscription Plan")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null ? _errorView() : _body()),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _body() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: const Text(
              "This subscribes you in our records only — it doesn't charge you yet, and doesn't currently change your commission rate. We'll let you know when billing and discounted rates go live.",
              style: TextStyle(color: AppColors.warning, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 16),
          if (_isActive)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: AppComponents.cardDecoration(),
              child: Row(children: [
                const Icon(Icons.check_circle, color: AppColors.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Subscribed to ${_current!.plan.name} · renews ${formatFriendlyDate(_current!.currentPeriodEnd)}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ]),
            )
          else
            const Text(
              "Choose a plan below.",
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          const SizedBox(height: 16),
          if (_plans.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No subscription plans are available right now.', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ...List.generate(_plans.length, (i) {
            final p = _plans[i];
            final selected = _selectedPlanId == p.id;
            final isCurrentPlan = _isActive && _current!.plan.id == p.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () => setState(() => _selectedPlanId = p.id),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                          if (isCurrentPlan) AppComponents.badge('Current plan', color: AppColors.success),
                          if (!isCurrentPlan) Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? AppColors.primaryDark : AppColors.textMuted),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${Currency.format(p.priceMonthly, decimals: 0)} / month', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(p.description, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          AppComponents.primaryButton(
            text: _acting
                ? 'Please wait…'
                : (_isActive && _current!.plan.id == _selectedPlanId ? 'Already subscribed' : 'Subscribe'),
            onPressed: (_acting || _selectedPlanId == null || (_isActive && _current!.plan.id == _selectedPlanId)) ? null : _subscribe,
          ),
          if (_isActive) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: _acting ? null : _cancel,
              child: const Text('Cancel subscription', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ],
      ),
    );
  }
}
