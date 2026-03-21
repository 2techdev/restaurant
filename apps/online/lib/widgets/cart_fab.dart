/// Floating cart button shown on the menu and product screens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gastrocore_online/core/theme/app_theme.dart';
import 'package:gastrocore_online/providers/cart_provider.dart';

class CartFab extends ConsumerWidget {
  const CartFab({super.key, required this.restaurantId});
  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    if (cart.isEmpty) return const SizedBox.shrink();

    final total = cart.subtotalCents;
    final wholes = total ~/ 100;
    final frac = (total % 100).toString().padLeft(2, '0');

    return FloatingActionButton.extended(
      backgroundColor: OnlineColors.primary,
      foregroundColor: Colors.white,
      elevation: 4,
      onPressed: () => context.go('/$restaurantId/cart'),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.shopping_cart_outlined, size: 22),
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${cart.itemCount}',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: OnlineColors.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      label: Text(
        'CHF $wholes.$frac',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    );
  }
}
