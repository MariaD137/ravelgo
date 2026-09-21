import 'package:flutter/material.dart';

/// Drop-in replacement for [MaterialPageRoute] with one difference: the
/// incoming screen fades in while sliding up slightly, instead of Flutter's
/// default per-platform push (a hard cut on the web, where every one of
/// these apps is also deployed). Used the same way:
///
///   Navigator.push(context, AppPageRoute(builder: (_) => NextScreen()));
///
/// Kept intentionally subtle (180ms, 12px of travel) so it reads as
/// polish rather than a distraction on a screen the driver may open dozens
/// of times a shift.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({required WidgetBuilder builder, super.settings, super.fullscreenDialog})
      : super(
          transitionDuration: const Duration(milliseconds: 180),
          reverseTransitionDuration: const Duration(milliseconds: 150),
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut, reverseCurve: Curves.easeIn);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
                child: child,
              ),
            );
          },
        );
}
