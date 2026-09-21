import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// The rider's own avatar, drawn from their real name.
///
/// RavelGo has no profile-photo upload for riders, so there is no photo to
/// show. The screens that needed an avatar used to ship a bundled stock
/// portrait of somebody who is not the user (assets/fake_profile.png), which
/// looked exactly like a real uploaded photo. Initials are honest: they are
/// derived from the name the backend actually holds, and they degrade to a
/// neutral person icon when the name isn't loaded yet.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 56});

  /// The full name as the backend returns it. Empty/null while loading.
  final String? name;
  final double size;

  /// Up to two initials: "Ada Obi" -> "AO", "ada" -> "A", "" -> "".
  static String initialsOf(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = initialsOf(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      // Black circle, white initials: the app's own high-contrast direction
      // (white background, black controls), not a photo-shaped grey blob.
      decoration: const BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
      child: initials.isEmpty
          ? Icon(Icons.person, size: size * 0.5, color: AppColors.surface)
          : Text(
              initials,
              style: TextStyle(
                fontSize: size * 0.38,
                fontWeight: FontWeight.w700,
                color: AppColors.surface,
              ),
            ),
    );
  }
}
