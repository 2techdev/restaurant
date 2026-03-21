/// Product card widget — Just Eat inspired horizontal layout.
/// Image on right, content on left, green "+" add button.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final isAvailable = product.isAvailable;

    return GestureDetector(
      onTap: isAvailable ? onTap : null,
      child: Opacity(
        opacity: isAvailable ? 1.0 : 0.5,
        child: Container(
          decoration: BoxDecoration(
            color: OnlineColors.bgCard,
            borderRadius: BorderRadius.circular(kRadiusLarge),
            border: Border.all(color: OnlineColors.divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left: text content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product name
                        Text(
                          product.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: OnlineColors.textPrimary,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),

                        // Description
                        if (product.description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            product.description!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: OnlineColors.textSecondary,
                              height: 1.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],

                        const Spacer(),
                        const SizedBox(height: 10),

                        // Price + add button
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              Money(product.price).format('CHF'),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: OnlineColors.textPrimary,
                              ),
                            ),
                            if (product.hasModifiers) ...[
                              const SizedBox(width: 6),
                              Text(
                                'ab',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: OnlineColors.textDim,
                                ),
                              ),
                            ],
                            const Spacer(),
                            _AddButton(
                              onTap: isAvailable ? onTap : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Right: image
                _ProductImage(
                  imageUrl: product.imageUrl,
                  isAvailable: isAvailable,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add button — green circle with "+"
// ---------------------------------------------------------------------------

class _AddButton extends StatelessWidget {
  const _AddButton({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: onTap != null ? OnlineColors.green : OnlineColors.border,
          shape: BoxShape.circle,
          boxShadow: onTap != null
              ? [
                  BoxShadow(
                    color: OnlineColors.green.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: const Icon(
          Icons.add_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Product image
// ---------------------------------------------------------------------------

class _ProductImage extends StatelessWidget {
  const _ProductImage({this.imageUrl, required this.isAvailable});
  final String? imageUrl;
  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(kRadiusLarge),
        bottomRight: Radius.circular(kRadiusLarge),
      ),
      child: SizedBox(
        width: 108,
        child: imageUrl != null
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: OnlineColors.pillActiveBg,
        child: Center(
          child: Icon(
            Icons.restaurant_rounded,
            size: 32,
            color: OnlineColors.primary.withValues(alpha: 0.5),
          ),
        ),
      );
}
