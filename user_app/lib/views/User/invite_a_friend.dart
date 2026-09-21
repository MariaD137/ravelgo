import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/referral_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Invite Friends, backed by the real referral programme.
///
/// This screen has twice been a fiction. It first promised "Earn ₦5,000" next
/// to a hardcoded code that didn't even match the different hardcoded code in
/// the share text; that was removed, leaving a share button with no link and
/// no referral at all. Everything here now comes from the backend: the code
/// is this rider's own (GET /api/riders/me/referral), the terms are whatever
/// an admin has configured, and the counts are real referrals.
///
/// When the programme is switched off the screen says so plainly rather than
/// advertising a reward nobody will be paid.
class InviteFriendsView extends StatefulWidget {
  const InviteFriendsView({super.key});

  @override
  State<InviteFriendsView> createState() => _InviteFriendsViewState();
}

class _InviteFriendsViewState extends State<InviteFriendsView> {
  ReferralSummary? _summary;
  bool _loading = true;
  String? _error;

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
      final summary = await ReferralApi.mine();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiFailure(e, what: 'your invite code');
        _loading = false;
      });
    }
  }

  String get _shareMessage {
    final summary = _summary;
    if (summary == null) return 'I use RavelGo to get around — you might like it too.';
    final reward = summary.program.refereeRewardAmount > 0
        ? ' You get ${Currency.format(summary.program.refereeRewardAmount, decimals: 0)} off your first rides.'
        : '';
    return 'I use RavelGo to get around — you might like it too.$reward '
        'Use my invite code ${summary.code} when you sign up.';
  }

  /// Share, and actually deal with what happens.
  ///
  /// The old version called share and walked away: not awaited, no error
  /// handling, no feedback. On web that matters, because the browser share
  /// sheet is unavailable on most desktops and the call falls back to a
  /// mailto: link or throws — either way the user saw nothing at all. The
  /// code is copied to the clipboard as a fallback so the screen is never a
  /// dead end.
  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await SharePlus.instance.share(ShareParams(text: _shareMessage));
      if (!mounted) return;
      if (result.status == ShareResultStatus.success) return;
      await _copyCode(messenger, 'Invite code copied — paste it to your friend.');
    } catch (_) {
      if (!mounted) return;
      await _copyCode(messenger, 'Sharing isn\'t available here, so your invite code was copied instead.');
    }
  }

  Future<void> _copyCode(ScaffoldMessengerState messenger, String message) async {
    final summary = _summary;
    if (summary == null) return;
    await Clipboard.setData(ClipboardData(text: _shareMessage));
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openClaimDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter an invite code'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Invite code'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter the code your friend gave you' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (code == null || !mounted) return;

    try {
      await ReferralApi.claim(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite code applied.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      // The backend's refusal messages are written for the user — show them.
      final message = e is ApiException && !e.isNetworkFailure && e.statusCode != 500
          ? e.message
          : describeApiFailure(e, what: 'that invite code');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        foregroundColor: AppColors.surface,
        title: const Text('Invite Friends'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _errorCard(_error!)
            else if (_summary != null)
              ..._loaded(_summary!),
          ],
        ),
      ),
      bottomNavigationBar: _summary == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 25),
              child: SizedBox(
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _share,
                  icon: const Icon(Icons.share, color: AppColors.surface),
                  label: const Text(
                    'Share',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.surface),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _errorCard(String message) {
    return _card(
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 32, color: AppColors.error),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: const Text('Try again')),
        ],
      ),
    );
  }

  List<Widget> _loaded(ReferralSummary summary) {
    final program = summary.program;
    return [
      _card(
        child: Column(
          children: [
            const Text('Tell your friends',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(
              program.enabled
                  ? _offerText(program)
                  : 'Share RavelGo with a friend. There\'s no invite reward running at the moment.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            _codeBlock(summary.code),
          ],
        ),
      ),
      if (program.enabled) ...[
        const SizedBox(height: 16),
        _card(
          child: Row(
            children: [
              _stat('Invited', '${summary.pending + summary.rewarded}'),
              _stat('Qualified', '${summary.rewarded}'),
              _stat('Earned', Currency.format(summary.totalEarned, decimals: 0)),
            ],
          ),
        ),
      ],
      if (summary.canClaim) ...[
        const SizedBox(height: 16),
        _card(
          child: Column(
            children: [
              const Text('Joined through a friend?',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text(
                'You can enter their code until your first completed ride.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _openClaimDialog,
                child: const Text('Enter invite code'),
              ),
            ],
          ),
        ),
      ] else if (summary.referredByCode != null) ...[
        const SizedBox(height: 16),
        _card(
          child: Text('You joined with invite code ${summary.referredByCode}.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ),
      ],
    ];
  }

  /// Describes the offer in the programme's real terms — the amount an admin
  /// configured, and how many rides the friend actually has to take.
  String _offerText(ReferralProgram program) {
    final trips = program.qualifyingTrips == 1
        ? 'their first ride'
        : 'their first ${program.qualifyingTrips} rides';
    final theirs = program.refereeRewardAmount > 0
        ? ' They get ${Currency.format(program.refereeRewardAmount, decimals: 0)} too.'
        : '';
    return 'Share your code. When a friend joins and completes $trips, '
        'you get ${Currency.format(program.rewardAmount, decimals: 0)} in your wallet.$theirs';
  }

  Widget _codeBlock(String code) {
    return Column(
      children: [
        const Text('YOUR INVITE CODE',
            style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invite code copied.')),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(code,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 3)),
                const SizedBox(width: 12),
                const Icon(Icons.copy, size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(1, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}
