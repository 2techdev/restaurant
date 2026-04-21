/// Product grid for the Kinetic sales shell.
///
/// Renders [filteredProductsProvider] as a dense tile grid matching the
/// SambaPOS reference (019da150) the user approved: each tile is a
/// zero-radius [catGreen] card with white body text (top-left) and a
/// white price chip (bottom-right).
///
/// Column count is responsive — driven by the rendering width rather than
/// a user toggle, because the middle "category column" already owns the
/// 1↔2 toggle via [productGridColumnsProvider]. A tablet at 1280dp hits the
/// 4-column breakpoint; the 7" pilot (~800dp product area) lands on 3.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';
import 'package:gastrocore_pos/features/audit_log/presentation/providers/audit_log_provider.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';

/// Column-count preference shared by the middle category column and — when
/// set to 1 — by a fallback single-column product list. The product grid
/// itself is responsive, so in the default (2-column category) mode this
/// value doesn't actually constrain the product grid.
final productGridColumnsProvider = StateProvider<int>((ref) => 2);

const int kProductGridMinColumns = 1;
const int kProductGridMaxColumns = 2;

int clampProductGridColumns(int n) =>
    n.clamp(kProductGridMinColumns, kProductGridMaxColumns);

void toggleProductGridColumns(WidgetRef ref) {
  final current = ref.read(productGridColumnsProvider);
  ref.read(productGridColumnsProvider.notifier).state =
      current == 1 ? 2 : 1;
}

// ---------------------------------------------------------------------------
// Tile sizing — picks a column count based on the grid's usable width.
// ---------------------------------------------------------------------------

const double _tileHeight = 112;
const double _tileMinWidth = 140;

int _columnsForWidth(double width) {
  if (width >= 880) return 5;
  if (width >= 720) return 4;
  if (width >= 520) return 3;
  return 2;
}

// ---------------------------------------------------------------------------
// ProductGrid
// ---------------------------------------------------------------------------

class ProductGrid extends ConsumerWidget {
  const ProductGrid({
    super.key,
    required this.onProductTap,
    this.cartQuantities = const <String, int>{},
  });

  final Map<String, int> cartQuantities;
  final void Function(ProductEntity) onProductTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(filteredProductsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    // Per-category hex colour lookup — drives POS-v2 category tinting on the
    // product tiles. When the DB is still loading, resolveCategoryColor falls
    // back to the warm orange default.
    final colorByCatId = <String, String?>{};
    final cats = categoriesAsync.asData?.value ?? const <CategoryEntity>[];
    for (final c in cats) {
      colorByCatId[c.id] = c.color;
    }

    return ColoredBox(
      color: GcColors.surface,
      child: productsAsync.when(
        data: (products) {
          if (products.isEmpty) return const _EmptyState();
          return LayoutBuilder(
            builder: (context, bc) {
              final cols = _columnsForWidth(bc.maxWidth);
              final tileWidth = (bc.maxWidth -
                      AppTokens.space16 - // outer padding
                      AppTokens.space8 * (cols - 1)) /
                  cols;
              final aspect = tileWidth / _tileHeight;

              return GridView.builder(
                key: ValueKey('product_grid_cols_$cols'),
                padding: const EdgeInsets.all(AppTokens.space8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: AppTokens.space8,
                  crossAxisSpacing: AppTokens.space8,
                  childAspectRatio: tileWidth < _tileMinWidth ? 1 : aspect,
                ),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final p = products[index];
                  return ProductCard(
                    key: ValueKey('product_card_${p.id}'),
                    product: p,
                    quantity: cartQuantities[p.id] ?? 0,
                    categoryColorHex: colorByCatId[p.categoryId],
                    // When the product is sold-out the tile greys out and
                    // taps are blocked — falling back to a snackbar keeps
                    // the operator informed instead of silently swallowing
                    // the input.
                    onTap: p.isAvailable
                        ? () => onProductTap(p)
                        : () => _showUnavailableSnackbar(context, p),
                    // Long-press opens the sold-out toggle sheet. Available
                    // to every role (audit-logged) so the cashier can 86
                    // the last schnitzel without finding a manager.
                    onLongPress: () => _showSoldOutSheet(context, ref, p),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: AppInsets.all16,
            child: Text(
              'Menü yüklenemedi: $err',
              style: GcText.bodySmall.copyWith(color: GcColors.error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ProductCard — zero-radius tile, name top-left, price bottom-right.
// ---------------------------------------------------------------------------

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onLongPress,
    this.quantity = 0,
    this.categoryColorHex,
  });

  final ProductEntity product;
  final VoidCallback onTap;

  /// Long-press gesture, wired in the product grid to the sold-out toggle
  /// sheet. Optional so isolated widget tests (e.g. [ProductGridTest]) can
  /// build the card without plumbing a sheet builder.
  final VoidCallback? onLongPress;

  final int quantity;

  /// Hex string from the product's [CategoryEntity.color]. When null or
  /// malformed the card falls back to the warm default.
  final String? categoryColorHex;

  @override
  Widget build(BuildContext context) {
    final style = resolveCategoryColor(categoryColorHex);
    final bg = style.bg;
    final fg = style.fg;
    final isUnavailable = !product.isAvailable;

    // a11y: flatten the product tile to a single button node with a
    // readable announcement ("Espresso, CHF 4.50, 2 im Warenkorb").
    // excludeSemantics: true on the wrapper prevents the three internal
    // Text widgets from showing up as separate leaves in the a11y tree.
    final cartHint = quantity > 0 ? ', $quantity im Warenkorb' : '';
    final unavailableHint = isUnavailable ? ', satışta değil' : '';
    final card = Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: darken(bg, 0.18),
        highlightColor: darken(bg, 0.12),
        child: Stack(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: kInsetHighlight, width: 2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.space8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: fg,
                          height: 1.15,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Text(
                        _formatCHF(product.price),
                        style: TextStyle(
                          fontFamily: 'WorkSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: fg,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (quantity > 0)
              Positioned(
                top: AppTokens.space4,
                right: AppTokens.space4,
                child: _QuantityBadge(quantity: quantity, tileColor: bg),
              ),
            if (isUnavailable)
              const Positioned.fill(
                child: _UnavailableOverlay(),
              ),
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      label: '${product.name}, ${_formatCHF(product.price)}$cartHint$unavailableHint',
      excludeSemantics: true,
      // Greyscale + dimmed opacity for sold-out tiles. The ColorFilter
      // runs on the painted pixels only — the InkWell inside still
      // responds to taps so we can route them to a snackbar.
      child: isUnavailable
          ? ColorFiltered(
              colorFilter: const ColorFilter.matrix(_kGreyscaleMatrix),
              child: Opacity(opacity: 0.65, child: card),
            )
          : card,
    );
  }

  static String _formatCHF(int cents) {
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    return 'CHF $whole.$frac';
  }
}

/// Luminance-preserving greyscale matrix (ITU-R BT.601 weights) used to
/// desaturate sold-out product tiles without touching the underlying
/// colour tokens. Applied via [ColorFiltered].
const List<double> _kGreyscaleMatrix = <double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0,      0,      0,      1, 0,
];

/// Centred "SATIŞTA DEĞİL" ribbon drawn across the unavailable tile. Sits
/// above the card so it is legible regardless of the underlying category
/// tint — the greyscale filter already desaturates the background.
class _UnavailableOverlay extends StatelessWidget {
  const _UnavailableOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space8,
            vertical: AppTokens.space4,
          ),
          color: Colors.black.withValues(alpha: 0.72),
          child: const Text(
            'SATIŞTA DEĞİL',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuantityBadge extends StatelessWidget {
  const _QuantityBadge({required this.quantity, required this.tileColor});
  final int quantity;
  final Color tileColor;

  @override
  Widget build(BuildContext context) {
    // POS v2: in-cart badge is a white circle with the category colour as
    // text — it reads as a numeric chip over the tile, not a coloured pill.
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Text(
        quantity > 9 ? '9+' : '$quantity',
        style: GcText.button.copyWith(
          fontSize: 11,
          color: tileColor,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sold-out toggle wiring — snackbar on blocked tap + long-press bottom sheet.
// ---------------------------------------------------------------------------

void _showUnavailableSnackbar(BuildContext context, ProductEntity product) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text('${product.name} şu anda satışta değil.'),
        duration: const Duration(seconds: 2),
      ),
    );
}

/// Opens a bottom sheet that flips [ProductEntity.isAvailable] and writes an
/// audit log entry. Every role is allowed to toggle — the audit trail is the
/// safeguard. The toggle uses the lightweight
/// [MenuRepositoryImpl.setProductAvailable] helper so we don't re-stamp every
/// product field on a gesture that might fire dozens of times during a shift.
Future<void> _showSoldOutSheet(
  BuildContext context,
  WidgetRef ref,
  ProductEntity product,
) async {
  final wasAvailable = product.isAvailable;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.space16,
            AppTokens.space8,
            AppTokens.space16,
            AppTokens.space16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                product.name,
                style: GcText.headline,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTokens.space4),
              Text(
                wasAvailable
                    ? 'Bu ürünü geçici olarak satışa kapatmak ister misiniz?'
                    : 'Bu ürünü tekrar satışa açmak ister misiniz?',
                style: GcText.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTokens.space16),
              FilledButton.icon(
                icon: Icon(wasAvailable
                    ? Icons.block_rounded
                    : Icons.check_circle_rounded),
                label: Text(
                  wasAvailable ? 'Satışa Kapat' : 'Satışa Aç',
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: AppTokens.space8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Vazgeç'),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (confirmed != true) return;

  final repo = ref.read(menuRepositoryProvider);
  final audit = ref.read(auditServiceProvider);
  final nextAvailable = !wasAvailable;

  try {
    await repo.setProductAvailable(product.id, isAvailable: nextAvailable);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Güncelleme başarısız: $e')),
      );
    }
    return;
  }

  // Record the flip in the audit log so the daily report can show who
  // 86'd what and when. Fire-and-forget: audit writes never block the UI.
  unawaited(
    audit.log(
      action: AuditAction.productAvailabilityChanged,
      entityType: 'product',
      entityId: product.id,
      oldValueJson: '{"isAvailable":$wasAvailable}',
      newValueJson: '{"isAvailable":$nextAvailable}',
      reason: product.name,
    ),
  );

  // Bust the cached product list so the grid repaints with the new state.
  ref.invalidate(productsProvider);
  ref.invalidate(adminProductsProvider);

  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          nextAvailable
              ? '${product.name} satışa açıldı.'
              : '${product.name} satışa kapatıldı.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restaurant_menu_rounded,
              size: 48, color: GcColors.outlineVariant),
          SizedBox(height: AppTokens.space8),
          Text(
            'Bu kategoride ürün yok',
            style: GcText.bodySmall,
          ),
        ],
      ),
    );
  }
}
