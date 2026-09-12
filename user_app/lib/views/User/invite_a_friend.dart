import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Invite friends to try RavelGo via the real platform share sheet
/// (share_plus). This used to promise "Earn ₦5,000" for 5 referred friends
/// completing 2 rides each, backed by a hardcoded fake referral code
/// ("HKPY8HGC5DET2" on screen, but a different made-up one, "RAVEL20", in the
/// actual share text) — there is no referral/rewards model anywhere in the
/// backend, so neither the code nor the reward was ever real. Removed rather
/// than reworded: sharing the app is a genuine, working feature on its own
/// and doesn't need an invented incentive to justify the screen.
class InviteFriendsView extends StatelessWidget {
  const InviteFriendsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 200,
              width: double.infinity,
              color: AppColors.textPrimary,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: const CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.surface,
                                child: Icon(Icons.arrow_back, color: AppColors.textPrimary),
                              ),
                            ),
                          ),
                          const Text(
                            "Invite Friends",
                            style: TextStyle(
                              color: AppColors.surface,
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 140,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textPrimary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(1, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Tell your friends",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Know someone who'd like RavelGo? Share it with them below.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 40),
                  Image.asset('assets/invite_a_refer.png', width: 110, height: 110, fit: BoxFit.fill),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 25),
        child: SizedBox(
          height: 55,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              SharePlus.instance.share(ShareParams(
                text: 'I use RavelGo to get around — you might like it too. Check it out!',
              ));
            },
            icon: const Icon(Icons.share, color: AppColors.surface),
            label: const Text(
              "Share",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.surface),
            ),
          ),
        ),
      ),
    );
  }
}
