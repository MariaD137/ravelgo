import 'package:ravelgo_user_app/services/api_client.dart';

/// The referral programme's current terms, as the backend reports them
/// (GET /api/settings/referral, and embedded in the summary below). Never
/// hardcoded in the app: what a referral is worth is an admin setting, and
/// the invite screen must describe whatever it actually is today.
class ReferralProgram {
  final bool enabled;
  final double rewardAmount;
  final double refereeRewardAmount;
  final int qualifyingTrips;

  const ReferralProgram({
    required this.enabled,
    required this.rewardAmount,
    required this.refereeRewardAmount,
    required this.qualifyingTrips,
  });

  factory ReferralProgram.fromJson(Map<String, dynamic> j) => ReferralProgram(
        enabled: j['enabled'] == true,
        rewardAmount: _d(j['rewardAmount']),
        refereeRewardAmount: _d(j['refereeRewardAmount']),
        qualifyingTrips: _i(j['qualifyingTrips'], fallback: 1),
      );

  /// Used only before the first load returns — renders as "off", which is
  /// the safe thing to show when we don't yet know the terms.
  static const unknown = ReferralProgram(
    enabled: false,
    rewardAmount: 0,
    refereeRewardAmount: 0,
    qualifyingTrips: 1,
  );
}

/// This rider's own referral standing (GET /api/riders/me/referral).
class ReferralSummary {
  final String code;
  final ReferralProgram program;

  /// Invites claimed but not yet qualified.
  final int pending;

  /// Invites that have paid out.
  final int rewarded;

  /// Total actually credited to this rider's wallet, in NGN.
  final double totalEarned;

  /// The code this rider themself joined with, if any.
  final String? referredByCode;

  /// Whether this rider could still enter someone's code.
  final bool canClaim;

  const ReferralSummary({
    required this.code,
    required this.program,
    required this.pending,
    required this.rewarded,
    required this.totalEarned,
    required this.referredByCode,
    required this.canClaim,
  });

  factory ReferralSummary.fromJson(Map<String, dynamic> j) => ReferralSummary(
        code: '${j['code'] ?? ''}',
        program: ReferralProgram.fromJson(
          (j['program'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        pending: _i(j['pending']),
        rewarded: _i(j['rewarded']),
        totalEarned: _d(j['totalEarned']),
        referredByCode: j['referredByCode']?.toString(),
        canClaim: j['canClaim'] == true,
      );
}

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int _i(dynamic v, {int fallback = 0}) =>
    v is num ? v.toInt() : int.tryParse('$v') ?? fallback;

class ReferralApi {
  /// My code, the current terms and how my invites are doing. The backend
  /// issues the code on first call, so there is no separate "create" step.
  static Future<ReferralSummary> mine() async {
    final data = await ApiClient.get('/api/riders/me/referral');
    return ReferralSummary.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Use someone else's code. The backend decides whether this is allowed —
  /// it refuses self-referral, a second claim, and any rider who has already
  /// completed a ride — and its message is shown to the user verbatim.
  static Future<void> claim(String code) async {
    await ApiClient.post('/api/riders/me/referral/claim', {'code': code.trim()});
  }
}
