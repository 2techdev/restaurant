/// Product detail screen — image, description, modifiers, quantity, add to cart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gastrocore_online/core/theme/app_theme.dart';
import 'package:gastrocore_online/core/utils/money.dart';
import 'package:gastrocore_online/domain/models/menu_models.dart';
import 'package:gastrocore_online/l10n/app_localizations.dart';
import 'package:gastrocore_online/providers/cart_provider.dart';
import 'package:gastrocore_online/providers/menu_provider.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.restaurantId,
    required this.productId,
  });

  final String restaurantId;
  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState
    extends ConsumerState<ProductDetailScreen> {
  int _quantity = 1;
  final Map<String, Set<String>> _selectedModifierIds = {};
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  OnlineProduct? _findProduct(OnlineMenu menu) {
    try {
      return menu.products
          .firstWhere((p) => p.id == widget.productId);
    } catch (_) {
      return null;
    }
  }

  void _initDefaults(OnlineProduct product) {
    if (_selectedModifierIds.isEmpty && product.hasModifiers) {
      for (final group in product.modifierGroups) {
        _selectedModifierIds[group.id] = group.modifiers
            .where((m) => m.isDefault)
            .map((m) => m.id)
            .toSet();
      }
    }
  }

  List<OnlineModifier> _getSelectedModifiers(OnlineProduct product) {
    return product.modifierGroups
        .expand((g) => g.modifiers)
        .where((m) =>
            (_selectedModifierIds[m.groupId] ?? {}).contains(m.id))
        .toList();
  }

  int _calculateTotal(OnlineProduct product) {
    final mods = _getSelectedModifiers(product);
    final modDelta =
        mods.fold(0, (sum, m) => sum + m.priceDelta);
    return (product.price + modDelta) * _quantity;
  }

  bool _isValid(OnlineProduct product) {
    for (final group in product.modifierGroups) {
      if (group.isRequired) {
        final count =
            (_selectedModifierIds[group.id] ?? {}).length;
        if (count < group.minSelections) return false;
      }
    }
    return true;
  }

  void _addToCart(OnlineProduct product) {
    if (!_isValid(product)) return;
    final mods = _getSelectedModifiers(product);
    ref.read(cartProvider.notifier).addProduct(
          product,
          quantity: _quantity,
          selectedModifiers: mods,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.itemAdded),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final menuAsync = ref.watch(menuProvider(widget.restaurantId));

    return menuAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: CircularProgressIndicator(color: OnlineColors.primary),
        ),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.errorLoadingMenu)),
      ),
      data: (menu) {
        final product = _findProduct(menu);
        if (product == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Product not found')),
          );
        }
        _initDefaults(product);
        return _buildScreen(context, l10n, product);
      },
    );
  }

  Widget _buildScreen(
    BuildContext context,
    AppLocalizations l10n,
    OnlineProduct product,
  ) {
    final total = _calculateTotal(product);

    return Scaffold(
      backgroundColor: OnlineColors.bgPage,
      body: CustomScrollView(
        slivers: [
          // Hero image + back button
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: OnlineColors.bgCard,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: CircleAvatar(
                backgroundColor: Colors.black38,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      size: 18, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: product.imageUrl != null
                  ? Image.network(product.imageUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: OnlineColors.primaryLight,
                        child: const Center(
                          child: Icon(Icons.restaurant,
                              size: 80, color: OnlineColors.primary),
                        ),
                      ))
                  : Container(
                      color: OnlineColors.primaryLight,
                      child: const Center(
                        child: Icon(Icons.restaurant,
                            size: 80, color: OnlineColors.primary),
                      ),
                    ),
            ),
          ),

          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                color: OnlineColors.bgCard,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(kRadiusXl)),
              ),
              margin: const EdgeInsets.only(top: 0),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name & price
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          Money(product.price).format('CHF'),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: OnlineColors.primary),
                        ),
                      ],
                    ),
                    if (product.description != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        product.description!,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                                color: OnlineColors.textSecondary,
                                height: 1.5),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),

          // Modifier groups
          for (final group in product.modifierGroups) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: _ModifierGroupSection(
                  group: group,
                  selectedIds:
                      _selectedModifierIds[group.id] ?? {},
                  onToggle: (modifierId) {
                    setState(() {
                      final sel =
                          _selectedModifierIds[group.id] ?? {};
                      if (group.isSingle) {
                        _selectedModifierIds[group.id] = {modifierId};
                      } else {
                        if (sel.contains(modifierId)) {
                          sel.remove(modifierId);
                        } else {
                          if (sel.length < group.maxSelections) {
                            sel.add(modifierId);
                          }
                        }
                        _selectedModifierIds[group.id] = sel;
                      }
                    });
                  },
                ),
              ),
            ),
          ],

          // Notes & quantity
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.notes,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: l10n.notesPlaceholder,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Quantity
                  Row(
                    children: [
                      Text(l10n.quantity,
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      _QuantityStepper(
                        quantity: _quantity,
                        onChanged: (q) => setState(() => _quantity = q),
                      ),
                    ],
                  ),
                  const SizedBox(height: 100), // space for bottom bar
                ],
              ),
            ),
          ),
        ],
      ),

      // Add to cart bottom bar
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: ElevatedButton(
            onPressed:
                _isValid(product) ? () => _addToCart(product) : null,
            child: Text(
              '${l10n.addToCart} — CHF ${(total ~/ 100)}.${(total % 100).toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modifier group section
// ---------------------------------------------------------------------------

class _ModifierGroupSection extends StatelessWidget {
  const _ModifierGroupSection({
    required this.group,
    required this.selectedIds,
    required this.onToggle,
  });

  final OnlineModifierGroup group;
  final Set<String> selectedIds;
  final void Function(String modifierId) onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: OnlineColors.divider),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: group.isRequired
                      ? OnlineColors.primaryLight
                      : OnlineColors.chipBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  group.isRequired ? l10n.required : l10n.optional,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: group.isRequired
                        ? OnlineColors.primary
                        : OnlineColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // Modifiers
        ...group.modifiers.map((mod) {
          final isSelected = selectedIds.contains(mod.id);
          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
            leading: group.isSingle
                ? Radio<String>(
                    value: mod.id,
                    groupValue:
                        selectedIds.isEmpty ? null : selectedIds.first,
                    activeColor: OnlineColors.primary,
                    onChanged: (_) => onToggle(mod.id),
                  )
                : Checkbox(
                    value: isSelected,
                    activeColor: OnlineColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    onChanged: (_) => onToggle(mod.id),
                  ),
            title: Text(
              mod.name,
              style: TextStyle(
                fontSize: 15,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            trailing: mod.priceDelta == 0
                ? Text(l10n.free,
                    style: const TextStyle(
                        color: OnlineColors.green,
                        fontWeight: FontWeight.w500))
                : Text(
                    '${mod.priceDelta > 0 ? '+' : ''}CHF ${(mod.priceDelta / 100).toStringAsFixed(2)}',
                    style: TextStyle(
                      color: mod.priceDelta > 0
                          ? OnlineColors.textSecondary
                          : OnlineColors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
            onTap: () => onToggle(mod.id),
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Quantity stepper
// ---------------------------------------------------------------------------

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.onChanged,
  });

  final int quantity;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepButton(
          icon: Icons.remove,
          onTap: quantity > 1 ? () => onChanged(quantity - 1) : null,
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add,
          onTap: () => onChanged(quantity + 1),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled ? OnlineColors.primary : OnlineColors.chipBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? Colors.white : OnlineColors.textDim,
        ),
      ),
    );
  }
}
