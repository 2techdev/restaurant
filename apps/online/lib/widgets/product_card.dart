/// Product card widget for the menu grid.
library;

import 'package:flutter/material.dart';
import 'package:gastrocore_online/core/theme/app_theme.dart';
import 'package:gastrocore_online/core/utils/money.dart';
import 'package:gastrocore_online/domain/models/menu_models.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  final OnlineProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: product.isAvailable ? onTap : null,
      child: Container(
        decoration: BoxDecoration(
          color: OnlineColors.bgCard,
          borderRadius: BorderRadius.circular(kRadiusMedium),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ProductImage(imageUrl: product.imageUrl),
                  if (!product.isAvailable)
                    Container(
                      color: Colors.black54,
                      alignment: Alignment.center,
                      child: const Text(
                        'Unavailable',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    Text(
                      product.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Description
                    if (product.description != null) ...[
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          product.description!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: OnlineColors.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ] else
                      const Spacer(),

                    const SizedBox(height: 8),

                    // Price row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          Money(product.price).format('CHF'),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: OnlineColors.primary),
                        ),
                        if (product.hasModifiers)
                          const Icon(
                            Icons.tune,
                            size: 16,
                            color: OnlineColors.textDim,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({this.imageUrl});
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null) {
      return Container(
        color: OnlineColors.primaryLight,
        child: const Center(
          child: Icon(
            Icons.restaurant,
            size: 40,
            color: OnlineColors.primary,
          ),
        ),
      );
    }
    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: OnlineColors.primaryLight,
        child: const Center(
          child: Icon(Icons.restaurant, size: 40, color: OnlineColors.primary),
        ),
      ),
    );
  }
}
