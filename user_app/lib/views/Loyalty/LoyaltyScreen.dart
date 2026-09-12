import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/loyalty_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Real loyalty tier progress (GET /api/riders/me/loyalty, computed live from
/// completed trips — never stored, so it can't drift) and real promo codes
/// (GET /api/promotions, POST /api/promotions/:code/redeem). Neither existed
/// anywhere in the app before this screen, despite the backend already
/// supporting both in full.
///
/// Disclosed rather than hidden: a redeemed code or loyalty tier is recorded
/// (PromotionRedemption row / tier computed from trip count), but neither
/// currently reduces what a fare actually charges — pricing.ts's fare
/// computation doesn't read either. Said plainly below instead of implying a
/// discount that isn't applied.
class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  bool _loading = true;
  String? _error;
  MyLoyalty? _mine;
  List<LoyaltyTier> _tiers = const [];
  List<Promotion> _promotions = const [];

  final _codeController = TextEditingController();
  bool _redeeming = false;
  String? _redeemMessage;
  bool _redeemSucceeded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([LoyaltyApi.myLoyalty(), LoyaltyApi.tiers(), LoyaltyApi.promotions()]);
      if (!mounted) return;
      setState(() {
        _mine = results[0] as MyLoyalty;
        _tiers = (results[1] as List<LoyaltyTier>)..sort((a, b) => a.minCompletedTrips.compareTo(b.minCompletedTrips));
        _promotions = results[2] as List<Promotion>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Could not load loyalty & promotions.';
        _loading = false;
      });
    }
  }

  Future<void> _redeem() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || _redeeming) return;
    setState(() {
      _redeeming = true;
      _redeemMessage = null;
    });
    try {
      final discount = await LoyaltyApi.redeem(code);
      if (!mounted) return;
      setState(() {
        _redeemSucceeded = true;
        _redeemMessage = 'Code redeemed — ${discount.toStringAsFixed(0)}% off is on your account.';
        _codeController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _redeemSucceeded = false;
        _redeemMessage = e is ApiException ? e.message : 'Could not redeem that code.';
      });
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  LoyaltyTier? get _nextTier {
    final trips = _mine?.completedTrips ?? 0;
    final upcoming = _tiers.where((t) => t.minCompletedTrips > trips).toList()
      ..sort((a, b) => a.minCompletedTrips.compareTo(b.minCompletedTrips));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textPrimary),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: const Text('Loyalty & promotions', style: TextStyle(color: AppColors.textPrimary)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null ? _errorView() : RefreshIndicator(onRefresh: _load, child: _body())),
    );
  }

  Widget _errorView() => ListView(
        children: [
          const SizedBox(height: 80),
          Icon(Icons.error_outline, size: 40, color: AppColors.error.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Center(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary))),
          const SizedBox(height: 12),
          Center(child: TextButton(onPressed: _load, child: const Text('Retry'))),
        ],
      );

  Widget _body() {
    final mine = _mine;
    final next = _nextTier;
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: const Text(
            "Your tier and redeemed codes are tracked here, but discounts aren't automatically applied to your fare yet.",
            style: TextStyle(color: AppColors.warning, fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.emoji_events_outlined, color: AppColors.primaryDark),
                const SizedBox(width: 8),
                Text(
                  mine?.currentTier != null ? '${mine!.currentTier!.name} tier' : 'No tier yet',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ]),
              const SizedBox(height: 6),
              Text('${mine?.completedTrips ?? 0} completed trips', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              if (mine?.currentTier?.perks != null) ...[
                const SizedBox(height: 6),
                Text(mine!.currentTier!.perks!, style: const TextStyle(fontSize: 13)),
              ],
              if (next != null) ...[
                const SizedBox(height: 10),
                Text(
                  '${next.minCompletedTrips - (mine?.completedTrips ?? 0)} more trip${next.minCompletedTrips - (mine?.completedTrips ?? 0) == 1 ? '' : 's'} to reach ${next.name}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        if (_tiers.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Tiers', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          ..._tiers.map((t) {
            final reached = (mine?.completedTrips ?? 0) >= t.minCompletedTrips;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Icon(reached ? Icons.check_circle : Icons.circle_outlined, size: 18, color: reached ? AppColors.success : AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${t.name} · ${t.minCompletedTrips}+ trips', style: const TextStyle(fontSize: 13.5)),
                ),
              ]),
            );
          }),
        ],
        const SizedBox(height: 20),
        const Text('Redeem a code', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'Promo code', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _redeeming ? null : _redeem,
              child: Text(_redeeming ? 'Please wait…' : 'Redeem'),
            ),
          ],
        ),
        if (_redeemMessage != null) ...[
          const SizedBox(height: 8),
          Text(_redeemMessage!, style: TextStyle(color: _redeemSucceeded ? AppColors.success : AppColors.error, fontSize: 13)),
        ],
        if (_promotions.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Available promotions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          ..._promotions.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.code, style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(p.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      Text('${p.discountPercent.toStringAsFixed(0)}% off', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              )),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No active promotions right now.', style: TextStyle(color: AppColors.textSecondary)),
          ),
      ],
    );
  }
}
