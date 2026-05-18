/// Combo (set menu) component picker dialog.
///
/// Triggered when the cashier taps a [ProductEntity] with `isCombo=true`.
/// We load the combo's component rows from `combo_items`, group them by
/// [ComboItemEntity.groupName] (null = fixed inclusion), and let the
/// cashier pick one row per group. On confirm, each chosen component is
/// added to the active ticket as its own cart line (open-price
/// override priced at zero so the combo's fixed-price product itself
/// carries the charge) — same lifecycle as a normal tap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/menu/data/repositories/menu_repository_impl.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/combo_item_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';

/// Show the combo picker. Returns `true` when the cashier confirmed
/// (and the parent + components have been added to the ticket).
Future<bool> showComboPickerDialog(
  BuildContext context, {
  required ProductEntity comboProduct,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _ComboPickerDialog(combo: comboProduct),
  );
  return ok ?? false;
}

class _ComboPickerDialog extends ConsumerStatefulWidget {
  const _ComboPickerDialog({required this.combo});
  final ProductEntity combo;

  @override
  ConsumerState<_ComboPickerDialog> createState() =>
      _ComboPickerDialogState();
}

class _ComboPickerDialogState extends ConsumerState<_ComboPickerDialog> {
  late Future<_PickerData> _future;

  /// itemProductId picked per group (null group = "fixed" — auto-picked).
  final Map<String?, String> _picked = {};

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  String _t(String tr, String de, String en, String fr, String it) {
    final lang = Localizations.localeOf(context).languageCode;
    switch (lang) {
      case 'de':
        return de;
      case 'en':
        return en;
      case 'fr':
        return fr;
      case 'it':
        return it;
      default:
        return tr;
    }
  }

  Future<_PickerData> _load() async {
    final repo = MenuRepositoryImpl(ref.read(databaseProvider));
    final components = await repo.getComboItems(widget.combo.id);
    final allProducts =
        ref.read(productsProvider).valueOrNull ?? const <ProductEntity>[];
    final byId = {for (final p in allProducts) p.id: p};

    // Auto-pick fixed (group == null) rows.
    for (final c in components.where((c) => c.groupName == null)) {
      _picked[null] = c.itemProductId;
    }
    return _PickerData(components: components, productsById: byId);
  }

  Future<void> _confirm(_PickerData data) async {
    // Verify each named group has a pick.
    final groups = <String>{};
    for (final c in data.components) {
      if (c.groupName != null && c.isRequired) groups.add(c.groupName!);
    }
    for (final g in groups) {
      if (_picked[g] == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_t(
            'Lütfen "$g" seçin',
            'Bitte „$g" wählen',
            'Please pick "$g"',
            'Veuillez choisir « $g »',
            'Seleziona "$g"',
          )),
          duration: const Duration(seconds: 2),
        ));
        return;
      }
    }
    setState(() => _submitting = true);

    final notifier = ref.read(currentTicketProvider.notifier);
    // Parent combo line carries the price. Components are added with
    // 0 price so the receipt shows the structure without double-billing.
    await notifier.addItem(widget.combo);

    // Add each selected/fixed component as a labelled open item (0 CHF).
    for (final c in data.components) {
      final selectedId = c.groupName == null
          ? c.itemProductId
          : _picked[c.groupName] ?? '';
      if (selectedId.isEmpty) continue;
      final product = data.productsById[selectedId];
      if (product == null) continue;
      final label =
          c.groupName == null ? product.name : '  • ${product.name}';
      await notifier.addOpenItem(
        name: label,
        priceCents: 0,
        taxGroup: product.taxGroup,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: GcColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.space20),
          child: FutureBuilder<_PickerData>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snap.data!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.fastfood_outlined,
                          color: GcColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(widget.combo.name,
                            style: GcText.headline),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.space12),
                  Flexible(child: _GroupList(
                    data: data,
                    picked: _picked,
                    onPick: (group, productId) =>
                        setState(() => _picked[group] = productId),
                  )),
                  const SizedBox(height: AppTokens.space16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: Text(_t('İptal', 'Abbrechen', 'Cancel',
                              'Annuler', 'Annulla')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed:
                              _submitting ? null : () => _confirm(data),
                          child: Text(_t('Ekle', 'Hinzufügen', 'Add',
                              'Ajouter', 'Aggiungi')),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PickerData {
  _PickerData({required this.components, required this.productsById});
  final List<ComboItemEntity> components;
  final Map<String, ProductEntity> productsById;
}

class _GroupList extends StatelessWidget {
  const _GroupList({
    required this.data,
    required this.picked,
    required this.onPick,
  });

  final _PickerData data;
  final Map<String?, String> picked;
  final void Function(String? group, String productId) onPick;

  @override
  Widget build(BuildContext context) {
    // Bucket by groupName, preserve insertion order.
    final groups = <String?, List<ComboItemEntity>>{};
    for (final c in data.components) {
      groups.putIfAbsent(c.groupName, () => <ComboItemEntity>[]).add(c);
    }
    final entries = groups.entries.toList();
    return ListView.builder(
      shrinkWrap: true,
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        return _GroupCard(
          group: e.key,
          components: e.value,
          productsById: data.productsById,
          picked: picked[e.key],
          onPick: (id) => onPick(e.key, id),
        );
      },
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.components,
    required this.productsById,
    required this.picked,
    required this.onPick,
  });

  final String? group;
  final List<ComboItemEntity> components;
  final Map<String, ProductEntity> productsById;
  final String? picked;
  final void Function(String productId) onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(AppTokens.space12),
      decoration: BoxDecoration(
        color: GcColors.surfaceContainerLowest,
        border: Border.all(color: GcColors.ghostBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            group ?? 'Dahil',
            style: GcText.labelTiny.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final c in components)
            _ComponentRow(
              component: c,
              product: productsById[c.itemProductId],
              isPicked: picked == c.itemProductId ||
                  (group == null && components.length == 1),
              isFixed: group == null,
              onTap: () => onPick(c.itemProductId),
            ),
        ],
      ),
    );
  }
}

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({
    required this.component,
    required this.product,
    required this.isPicked,
    required this.isFixed,
    required this.onTap,
  });

  final ComboItemEntity component;
  final ProductEntity? product;
  final bool isPicked;
  final bool isFixed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = product?.name ?? '(missing #${component.itemProductId})';
    return InkWell(
      onTap: isFixed ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(
              isFixed
                  ? Icons.lock_outline
                  : (isPicked
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off),
              size: 18,
              color: isPicked ? GcColors.primary : GcColors.outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                component.quantity > 1
                    ? '${component.quantity}× $name'
                    : name,
                style: GcText.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
