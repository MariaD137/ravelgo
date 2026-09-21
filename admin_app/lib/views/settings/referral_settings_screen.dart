import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';
import 'package:ravelgo_admin/widgets/pagination_bar.dart';

/// The referral programme: its terms, and every referral running against them.
///
/// Turning this on starts crediting real money to real rider wallets when a
/// referred rider completes the configured number of trips, so the switch is
/// behind a confirmation and the backend independently requires
/// settings:write and audits every change.
class ReferralSettingsScreen extends StatefulWidget {
  const ReferralSettingsScreen({super.key});

  @override
  State<ReferralSettingsScreen> createState() => _ReferralSettingsScreenState();
}

class _ReferralSettingsScreenState extends State<ReferralSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  ReferralProgram? _program;

  final _rewardController = TextEditingController();
  final _refereeRewardController = TextEditingController();
  final _tripsController = TextEditingController();

  List<AdminReferral> _referrals = const [];
  String? _statusFilter;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rewardController.dispose();
    _refereeRewardController.dispose();
    _tripsController.dispose();
    super.dispose();
  }

  Future<void> _load({int? page}) async {
    if (page != null) _page = page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final program = await AdminApi.referralProgram();
      final referrals = await AdminApi.referrals(status: _statusFilter, page: _page);
      if (!mounted) return;
      if (referrals.isPastEnd) return await _load(page: referrals.totalPages);
      setState(() {
        _program = program;
        _rewardController.text = program.rewardAmount.toStringAsFixed(0);
        _refereeRewardController.text = program.refereeRewardAmount.toStringAsFixed(0);
        _tripsController.text = '${program.qualifyingTrips}';
        _referrals = referrals.items;
        _total = referrals.total;
        _totalPages = referrals.totalPages;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiFailure(e, what: 'the referral programme');
        _loading = false;
      });
    }
  }

  Future<void> _save({bool? enabled}) async {
    if (_saving) return;
    final reward = double.tryParse(_rewardController.text.trim());
    final refereeReward = double.tryParse(_refereeRewardController.text.trim());
    final trips = int.tryParse(_tripsController.text.trim());
    if (reward == null || reward < 0 || refereeReward == null || refereeReward < 0) {
      return _toast('Rewards must be zero or more.');
    }
    if (trips == null || trips < 1) {
      return _toast('Qualifying rides must be at least 1.');
    }

    // Switching the programme ON is the moment money starts moving.
    if (enabled == true) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Turn the referral programme on?'),
          content: Text(
            'Every rider who completes $trips ride${trips == 1 ? '' : 's'} after using an '
            'invite code will credit ${Currency.format(reward, decimals: 0)} to the rider who '
            'invited them'
            '${refereeReward > 0 ? ', and ${Currency.format(refereeReward, decimals: 0)} to themselves' : ''}. '
            'This spends real money.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Turn on')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      final updated = await AdminApi.updateReferralProgram(
        enabled: enabled,
        rewardAmount: reward,
        refereeRewardAmount: refereeReward,
        qualifyingTrips: trips,
      );
      if (!mounted) return;
      setState(() {
        _program = updated;
        _saving = false;
      });
      _toast('Referral programme updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(describeApiFailure(e, what: 'this change'));
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Referral Programme'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: (_loading || _saving) ? null : () => _load(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView(_error!)
              : _content(),
    );
  }

  Widget _errorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => _load(), child: const Text('Try again')),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final program = _program!;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppComponents.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Programme', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        AppComponents.badge(
                          program.enabled ? 'On' : 'Off',
                          color: program.enabled ? AppColors.success : AppColors.textMuted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'While this is off, no invite code can be claimed and nothing is paid. '
                      'Referrals already claimed stay pending and pay out if it is turned back on.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    _numberField(_rewardController, 'Reward to the inviter (${Currency.symbol})'),
                    const SizedBox(height: 12),
                    _numberField(
                        _refereeRewardController, 'Reward to the new rider (${Currency.symbol}, 0 = none)'),
                    const SizedBox(height: 12),
                    _numberField(_tripsController, 'Rides the new rider must complete'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving ? null : () => _save(),
                            child: Text(_saving ? 'Saving…' : 'Save terms'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving ? null : () => _save(enabled: !program.enabled),
                            child: Text(program.enabled ? 'Turn off' : 'Turn on'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text('Referrals', style: TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  for (final status in const [null, 'PENDING', 'REWARDED'])
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilterChip(
                        label: Text(status ?? 'All'),
                        selected: _statusFilter == status,
                        onSelected: (_) {
                          _statusFilter = status;
                          _load(page: 1);
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_referrals.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text('No referrals yet.',
                        style: TextStyle(color: AppColors.textMuted)),
                  ),
                )
              else
                for (final referral in _referrals) _referralTile(referral),
            ],
          ),
        ),
        PaginationBar(
          page: _page,
          totalPages: _totalPages,
          total: _total,
          itemLabel: 'referrals',
          busy: _loading,
          onPageChanged: (p) => _load(page: p),
        ),
      ],
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }

  Widget _referralTile(AdminReferral referral) {
    final rewarded = referral.status == 'REWARDED';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AppComponents.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${referral.referrerName.isEmpty ? referral.referrerEmail : referral.referrerName}'
                  '  →  '
                  '${referral.refereeName.isEmpty ? referral.refereeEmail : referral.refereeName}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              AppComponents.badge(
                rewarded ? 'Rewarded' : 'Pending',
                color: rewarded ? AppColors.success : AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Code ${referral.code} · joined ${formatFriendlyDate(referral.createdAt)}'
            '${rewarded && referral.referrerRewardAmount != null ? ' · paid ${Currency.format(referral.referrerRewardAmount!, decimals: 0)}' : ''}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
