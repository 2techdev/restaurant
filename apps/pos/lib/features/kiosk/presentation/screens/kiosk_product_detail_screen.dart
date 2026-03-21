/// Product detail screen for modifier selection and quantity input.
///
/// Shows the product image, description, all modifier groups (rendered as
/// radio/checkbox tiles), a quantity stepper, and an "Add to Cart" button.
/// Navigates back to the menu after adding.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/utils/money.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/providers/kiosk_provider.dart';
import 'package:gastrocore_pos/features/kiosk/router/kiosk_router.dart';
import 'package:gastrocore_pos/features/kiosk/theme/kiosk_theme.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_language_screen.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_welcome_screen.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/modifier_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';

class KioskProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;
  const KioskProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<KioskProductDetailScreen> createState() =>
      _KioskProductDetailScreenState();
}

class _KioskProductDetailScreenState
    extends ConsumerState<KioskProductDetailScreen> {
  int _quantity = 1;
  // groupId → set of selected modifier IDs
  final Map<String, Set<String>> _selectedModifiers = {};

  void _toggleModifier(
    ModifierGroupEntity group,
    ModifierEntity modifier,
  ) {
    setState(() {
      final selected = _selectedModifiers[group.id] ?? {};
      if (group.selectionType == ModifierSelectionType.single) {
        // Radio: replace selection
        _selectedModifiers[group.id] = {modifier.id};
      } else {
        // Checkbox: toggle
        if (selected.contains(modifier.id)) {
          selected.remove(modifier.id);
        } else {
          selected.add(modifier.id);
        }
        _selectedModifiers[group.id] = selected;
      }
    });
  }

  bool _isSelected(String groupId, String modifierId) {
    return (_selectedModifiers[groupId] ?? {}).contains(modifierId);
  }

  List<OrderItemModifierEntity> _buildModifiers(ProductEntity product) {
    final result = <OrderItemModifierEntity>[];
    for (final group in product.modifierGroups) {
      final selectedIds = _selectedModifiers[group.id] ?? {};
      for (final mod in group.modifiers) {
        if (selectedIds.contains(mod.id)) {
          result.add(OrderItemModifierEntity(
            id: 'tmp-${mod.id}',
            orderItemId: '',
            modifierId: mod.id,
            modifierName: mod.name,
            priceDelta: mod.priceDelta,
          ));
        }
      }
    }
    return result;
  }

  bool _canAdd(ProductEntity product) {
    for (final group in product.modifierGroups) {
      if (!group.isRequired) continue;
      final selected = (_selectedModifiers[group.id] ?? {}).length;
      if (selected < group.minSelections) return false;
    }
    return true;
  }

  int _computeTotalPrice(ProductEntity product) {
    final modDelta = _selectedModifiers.values
        .expand((ids) => ids)
        .map((id) {
          for (final group in product.modifierGroups) {
            for (final mod in group.modifiers) {
              if (mod.id == id) return mod.priceDelta;
            }
          }
          return 0;
        })
        .fold<int>(0, (s, d) => s + d);
    return (product.price + modDelta) * _quantity;
  }

  void _addToCart(ProductEntity product) {
    if (!_canAdd(product)) return;
    ref.read(kioskSessionProvider.notifier).addItem(
      product,
      quantity: _quantity,
      modifiers: _buildModifiers(product),
    );
    context.go(KioskRoutes.menu);
  }

  @override
  Widget build(BuildContext context) {
    final productAsync =
        ref.watch(kioskProductByIdProvider(widget.productId));

    return Scaffold(
      backgroundColor: KioskColors.bgPage,
      body: productAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (product) {
          if (product == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Product not found'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go(KioskRoutes.menu),
                    child: const Text('Back to Menu'),
                  ),
                ],
              ),
            );
          }
          return _ProductDetailBody(
            product: product,
            quantity: _quantity,
            selectedModifiers: _selectedModifiers,
            totalPrice: _computeTotalPrice(product),
            canAdd: _canAdd(product),
            onQuantityChanged: (q) => setState(() => _quantity = q),
            onToggleModifier: _toggleModifier,
            isSelected: _isSelected,
            onAddToCart: () => _addToCart(product),
            onBack: () => context.go(KioskRoutes.menu),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail body
// ---------------------------------------------------------------------------

class _ProductDetailBody extends StatelessWidget {
  final ProductEntity product;
  final int quantity;
  final Map<String, Set<String>> selectedModifiers;
  final int totalPrice;
  final bool canAdd;
  final ValueChanged<int> onQuantityChanged;
  final void Function(ModifierGroupEntity, ModifierEntity) onToggleModifier;
  final bool Function(String groupId, String modifierId) isSelected;
  final VoidCallback onAddToCart;
  final VoidCallback onBack;

  const _ProductDetailBody({
    required this.product,
    required this.quantity,
    required this.selectedModifiers,
    required this.totalPrice,
    required this.canAdd,
    required this.onQuantityChanged,
    required this.onToggleModifier,
    required this.isSelected,
    required this.onAddToCart,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          _DetailHeader(product: product, onBack: onBack),

          // ── Scrollable content ────────────────────────────────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: product image + description
                SizedBox(
                  width: 340,
                  child: _ProductSummaryPanel(product: product),
                ),

                // Divider
                Container(width: 1, color: KioskColors.border),

                // Right: modifiers + quantity + CTA
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Modifier groups
                        ...product.modifierGroups.map((group) =>
                            _ModifierGroupSection(
                              group: group,
                              isSelected: isSelected,
                              onToggle: onToggleModifier,
                            )),

                        if (product.modifierGroups.isNotEmpty)
                          const SizedBox(height: 24),

                        // Quantity stepper
                        _QuantityStepper(
                          quantity: quantity,
                          onChanged: onQuantityChanged,
                        ),

                        const SizedBox(height: 32),

                        // Add to cart button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: canAdd ? onAddToCart : null,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 20,
                              ),
                              backgroundColor: canAdd
                                  ? KioskColors.primary
                                  : KioskColors.border,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_shopping_cart_rounded,
                                    size: 24),
                                const SizedBox(width: 12),
                                Text(
                                  'Add to Cart · ${Money(totalPrice).format('CHF')}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (!canAdd)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'Please make all required selections',
                              style: TextStyle(
                                fontSize: 14,
                                color: KioskColors.error,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Step indicator ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: const KioskStepIndicator(currentStep: 1),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _DetailHeader extends StatelessWidget {
  final ProductEntity product;
  final VoidCallback onBack;

  const _DetailHeader({required this.product, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: KioskColors.bgCard,
        border: Border(bottom: BorderSide(color: KioskColors.border)),
      ),
      child: Row(
        children: [
          KioskBackButton(onTap: onBack),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              product.name,
              style: Theme.of(context).textTheme.headlineMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            Money(product.price).format('CHF'),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: KioskColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Product summary panel (left column)
// ---------------------------------------------------------------------------

class _ProductSummaryPanel extends StatelessWidget {
  final ProductEntity product;
  const _ProductSummaryPanel({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KioskColors.bgCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          SizedBox(
            height: 280,
            width: double.infinity,
            child: product.imagePath != null
                ? Image.asset(
                    product.imagePath!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _imagePlaceholder(product.name),
                  )
                : _imagePlaceholder(product.name),
          ),

          // Description
          if (product.description != null &&
              product.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                product.description!,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: KioskColors.textSecondary,
                      height: 1.5,
                    ),
              ),
            ),

          // Prep time badge
          if (product.prepTimeMinutes != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _PillBadge(
                icon: Icons.timer_outlined,
                label: '~${product.prepTimeMinutes} min',
              ),
            ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder(String name) {
    return Container(
      color: KioskColors.bgCardAlt,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.restaurant_menu_rounded,
            size: 64,
            color: KioskColors.textDim,
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: const TextStyle(
              fontSize: 16,
              color: KioskColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _PillBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: KioskColors.bgCardAlt,
        borderRadius: BorderRadius.circular(kKioskRadiusSmall),
        border: Border.all(color: KioskColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: KioskColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: KioskColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modifier group section
// ---------------------------------------------------------------------------

class _ModifierGroupSection extends StatelessWidget {
  final ModifierGroupEntity group;
  final bool Function(String groupId, String modifierId) isSelected;
  final void Function(ModifierGroupEntity, ModifierEntity) onToggle;

  const _ModifierGroupSection({
    required this.group,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                group.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KioskColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              if (group.isRequired)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: KioskColors.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Required',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: KioskColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: group.modifiers.map((mod) {
              final selected = isSelected(group.id, mod.id);
              return _ModifierChip(
                modifier: mod,
                isSelected: selected,
                onTap: () => onToggle(group, mod),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ModifierChip extends StatelessWidget {
  final ModifierEntity modifier;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModifierChip({
    required this.modifier,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? KioskColors.primaryContainer
              : KioskColors.bgCardAlt,
          borderRadius: BorderRadius.circular(kKioskRadiusMedium),
          border: Border.all(
            color: isSelected ? KioskColors.primary : KioskColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: KioskColors.primary,
                ),
              ),
            Text(
              modifier.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? KioskColors.primary
                    : KioskColors.textPrimary,
              ),
            ),
            if (modifier.priceDelta != 0) ...[
              const SizedBox(width: 8),
              Text(
                modifier.priceDelta > 0
                    ? '+${Money(modifier.priceDelta).format('CHF')}'
                    : Money(modifier.priceDelta).format('CHF'),
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected
                      ? KioskColors.primaryDark
                      : KioskColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quantity stepper
// ---------------------------------------------------------------------------

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final ValueChanged<int> onChanged;

  const _QuantityStepper({
    required this.quantity,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Quantity',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: KioskColors.textPrimary,
          ),
        ),
        const Spacer(),
        _StepperButton(
          icon: Icons.remove,
          onTap: quantity > 1 ? () => onChanged(quantity - 1) : null,
        ),
        SizedBox(
          width: 64,
          child: Center(
            child: Text(
              '$quantity',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: KioskColors.textPrimary,
              ),
            ),
          ),
        ),
        _StepperButton(
          icon: Icons.add,
          onTap: () => onChanged(quantity + 1),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepperButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: enabled ? KioskColors.bgCardAlt : KioskColors.border,
          borderRadius: BorderRadius.circular(kKioskRadiusMedium),
          border: Border.all(
            color: enabled ? KioskColors.border : KioskColors.border,
          ),
        ),
        child: Icon(
          icon,
          size: 24,
          color: enabled ? KioskColors.textPrimary : KioskColors.textDim,
        ),
      ),
    );
  }
}
