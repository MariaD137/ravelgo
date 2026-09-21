import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// A single skeleton block that sweeps a soft highlight left-to-right on a
/// loop — stands in for a piece of content (a line of text, an avatar, a
/// card) while its real data is still loading. Monochrome, matching the
/// app's black-and-white surfaces: no color is introduced just to animate.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const ShimmerBox({super.key, this.width, this.height = 14, this.radius = AppRadius.small});

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2 * t, 0),
              end: Alignment(1.0 + 2 * t, 0),
              colors: const [
                AppColors.surfaceElevated,
                Color(0xFFEAEAEA),
                AppColors.surfaceElevated,
              ],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

/// A skeleton standing in for one row of `MyTripsScreen`-style list content:
/// a leading icon circle, two lines of text, a trailing value. Reused
/// wherever a screen lists cards of that shape (trips, deliveries, rentals,
/// documents, payouts) so the loading state previews the layout that is
/// about to arrive instead of a spinner unrelated to it.
class ShimmerListTile extends StatelessWidget {
  const ShimmerListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppComponents.cardDecoration(),
      child: Row(
        children: [
          const ShimmerBox(width: 24, height: 24, radius: AppRadius.pill),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: MediaQuery.sizeOf(context).width * 0.5, height: 14),
                const SizedBox(height: 8),
                const ShimmerBox(width: 120, height: 11),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const ShimmerBox(width: 48, height: 14),
        ],
      ),
    );
  }
}

/// A skeleton for a single-record detail screen (trip/delivery/rental
/// detail): a title line, a couple of body lines, and a card-shaped block —
/// the loading stand-in for screens that show one thing, not a list.
class ShimmerDetail extends StatelessWidget {
  const ShimmerDetail({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const ShimmerBox(width: 180, height: 20),
        const SizedBox(height: 12),
        ShimmerBox(width: MediaQuery.sizeOf(context).width * 0.6, height: 13),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: AppComponents.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShimmerBox(width: 140, height: 14),
              const SizedBox(height: 10),
              ShimmerBox(width: MediaQuery.sizeOf(context).width * 0.8, height: 12),
              const SizedBox(height: 8),
              ShimmerBox(width: MediaQuery.sizeOf(context).width * 0.4, height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

/// A vertical stack of [ShimmerListTile]s, the drop-in replacement for
/// `Center(child: CircularProgressIndicator())` on any screen whose loaded
/// content is a list of cards.
class ShimmerList extends StatelessWidget {
  final int itemCount;
  final EdgeInsetsGeometry padding;

  const ShimmerList({super.key, this.itemCount = 5, this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8)});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => const ShimmerListTile(),
    );
  }
}
