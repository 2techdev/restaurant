/// Loading state widgets following the Stitch "Precision POS Framework".
///
/// Provides three loading patterns:
///
/// - [PosLoadingOverlay] — Full-screen semi-transparent overlay with a
///   spinner and optional message. Used for blocking operations.
///
/// - [PosShimmerCard] — Animated shimmer placeholder for cards and list
///   items. Uses surface hierarchy shift for the shimmer gradient.
///
/// - [PosLoadingIndicator] — Inline circular spinner for compact spaces.
///
/// All follow the dark theme with surface-appropriate colors.
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// PosLoadingOverlay
// ---------------------------------------------------------------------------

/// A full-screen, semi-transparent overlay with a centered spinner and
/// optional message text. Use for blocking async operations like
/// payment processing or shift closing.
///
/// ```dart
/// Stack(
///   children: [
///     MainContent(),
///     if (isProcessing)
///       PosLoadingOverlay(message: 'Processing payment...'),
///   ],
/// )
/// ```
class PosLoadingOverlay extends StatelessWidget {
  const PosLoadingOverlay({
    super.key,
    this.message,
  });

  /// Optional message shown below the spinner.
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgOverlay,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 20),
              Text(
                message!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PosShimmerCard
// ---------------------------------------------------------------------------

/// An animated shimmer placeholder that mimics content loading.
///
/// The shimmer gradient sweeps from [AppColors.surfaceContainerLow] through
/// [AppColors.surfaceContainerHigh] and back, following the Stitch surface
/// hierarchy for a natural dark-theme look.
///
/// ```dart
/// PosShimmerCard(height: 80, width: double.infinity)
/// ```
class PosShimmerCard extends StatefulWidget {
  const PosShimmerCard({
    super.key,
    this.height = 80,
    this.width = double.infinity,
    this.borderRadius = 12,
  });

  /// Card height.
  final double height;

  /// Card width. Defaults to full width.
  final double width;

  /// Corner radius. Defaults to 12.
  final double borderRadius;

  @override
  State<PosShimmerCard> createState() => _PosShimmerCardState();
}

class _PosShimmerCardState extends State<PosShimmerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value, 0),
              colors: const [
                AppColors.surfaceContainerLow,
                AppColors.surfaceContainerHigh,
                AppColors.surfaceContainerLow,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}


// ---------------------------------------------------------------------------
// PosLoadingIndicator
// ---------------------------------------------------------------------------

/// A compact inline circular spinner for use in buttons, list items,
/// or other tight spaces.
///
/// ```dart
/// Row(
///   children: [
///     PosLoadingIndicator(size: 16),
///     SizedBox(width: 8),
///     Text('Syncing...'),
///   ],
/// )
/// ```
class PosLoadingIndicator extends StatelessWidget {
  const PosLoadingIndicator({
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = 2.5,
  });

  /// Diameter of the spinner. Defaults to 24.
  final double size;

  /// Spinner color. Defaults to [AppColors.accent].
  final Color? color;

  /// Width of the spinner stroke. Defaults to 2.5.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(
          color ?? AppColors.accent,
        ),
      ),
    );
  }
}
