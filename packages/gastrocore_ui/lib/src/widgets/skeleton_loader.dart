/// Shimmer / skeleton loading placeholder.
library;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A shimmer-animated placeholder that mimics the shape of content while
/// it loads.
///
/// ```dart
/// // Single skeleton block
/// SkeletonLoader(width: double.infinity, height: 60)
///
/// // Skeleton list
/// SkeletonList(itemHeight: 72, itemCount: 5)
/// ```
class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
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
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          color: AppColors.surfaceContainerHigh
              .withValues(alpha: _animation.value),
        ),
      ),
    );
  }
}

/// A column of [SkeletonLoader] items with consistent spacing.
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final double spacing;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 72,
    this.spacing = 8,
    this.borderRadius = 12,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: List.generate(itemCount, (i) {
          return Padding(
            padding: EdgeInsets.only(bottom: i < itemCount - 1 ? spacing : 0),
            child: SkeletonLoader(
              height: itemHeight,
              borderRadius: borderRadius,
            ),
          );
        }),
      ),
    );
  }
}

/// A grid of [SkeletonLoader] items.
class SkeletonGrid extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final int crossAxisCount;
  final double spacing;

  const SkeletonGrid({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 100,
    this.crossAxisCount = 2,
    this.spacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: MediaQuery.sizeOf(context).width /
            crossAxisCount /
            itemHeight,
      ),
      itemCount: itemCount,
      itemBuilder: (_, __) => const SkeletonLoader(height: double.infinity),
    );
  }
}
