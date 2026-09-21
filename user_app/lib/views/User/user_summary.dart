import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/components/initials_avatar.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/auth_service.dart';
import 'package:ravelgo_user_app/services/rider_api.dart';
import 'package:ravelgo_user_app/views/bottommenu/BottomNavigationView.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// The rider's own profile card, opened from the drawer.
///
/// This screen used to show a stock portrait, the name "Thelma Ibeh", a
/// "4.55 Rating" and three cards captioned "Customer ratings" / "Acceptance
/// rate" / "Acceptance rate" with no values under them — none of it real,
/// none of it this rider's, and acceptance rate is a driver metric that does
/// not exist for riders at all. It now shows what the backend actually holds
/// for the signed-in rider (GET /api/riders/me) and nothing else.
class UserSummary extends StatefulWidget {
  const UserSummary({Key? key}) : super(key: key);

  @override
  State<UserSummary> createState() => _UserSummaryState();
}

class _UserSummaryState extends State<UserSummary> {
  String? _name;
  String? _email;
  String? _error;
  bool _loading = true;

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
      final me = await RiderApi.getMe();
      if (!mounted) return;
      setState(() {
        _name = me == null
            ? null
            : [me['firstName'], me['lastName']]
                .where((e) => e != null && '$e'.trim().isNotEmpty)
                .join(' ')
                .trim();
        _email = me?['email']?.toString() ?? AuthService.email;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Say which problem this is — a dead connection, an expired session
        // and a server fault need different things from the rider.
        _error = describeApiFailure(e, what: 'your profile');
        _email = AuthService.email;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),

              /// Back Button
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios),
                ),
              ),

              const SizedBox(height: 20),

              InitialsAvatar(name: _name, size: 72),

              const SizedBox(height: 16),

              Text(
                _loading
                    ? 'Loading…'
                    : ((_name?.isNotEmpty ?? false)
                        ? _name!
                        : (_email ?? 'Rider')),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),

              if (!_loading && (_email?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 6),
                Text(
                  _email!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _load,
                  child: const Text('Try again'),
                ),
              ],

              const SizedBox(height: 40),

              /// View More
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  BottomNavigationView.globalKey.currentState?.changeTab(3);
                },
                child: const Text(
                  "View more details",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
