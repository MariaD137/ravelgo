import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// The shared "nothing to show" / "couldn't load" body. Every list screen
/// used to write its own private `_empty()` with the same icon-title-
/// subtitle-retry shape and slightly different spacing; this is that widget
/// pulled out once so a fix or a restyle applies everywhere at once.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;
  final String retryLabel;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onRetry,
    this.retryLabel = "Try again",
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Icon(icon, size: 56, color: AppColors.textMuted),
        const SizedBox(height: AppSpacing.base),
        Center(child: Text(title, style: AppTypography.title.copyWith(color: AppColors.textPrimary))),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(subtitle, textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: AppSpacing.md),
          Center(child: TextButton(onPressed: onRetry, child: Text(retryLabel))),
        ],
      ],
    );
  }
}

/// Switches between a skeleton, an error/empty state, and real content with
/// a soft cross-fade instead of the content silently popping into place —
/// the one place list screens get their "loading -> here's your data"
/// motion, without every screen wiring its own AnimatedSwitcher.
class AsyncBody extends StatelessWidget {
  /// A stable identity for the currently-shown child (e.g. "loading",
  /// "error", "empty", "data:<count>") so AnimatedSwitcher knows a real
  /// transition happened rather than a rebuild of the same state.
  final String stateKey;
  final Widget child;
  final Duration duration;

  const AsyncBody({super.key, required this.stateKey, required this.child, this.duration = const Duration(milliseconds: 220)});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }
}
