import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/models.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import 'menu_provider.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(categoriesProvider);
    final prodsAsync = ref.watch(productsProvider);
    final selectedId = ref.watch(selectedCategoryIdProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Speisekarte', style: theme.textTheme.headlineMedium),
                    Text('Kategorien und Produkte verwalten', style: theme.textTheme.bodyMedium),
                  ],
                ),
                const Spacer(),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Produkt hinzufügen'),
                  onPressed: () => _showProductDialog(context, ref, null, selectedId),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth > 700;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 220,
                        child: _CategoriesPanel(
                          catsAsync: catsAsync,
                          selectedId: selectedId,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _ProductsPanel(
                          prodsAsync: prodsAsync,
                          selectedCategoryId: selectedId,
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    SizedBox(
                      height: 140,
                      child: _CategoriesPanel(
                        catsAsync: catsAsync,
                        selectedId: selectedId,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _ProductsPanel(
                        prodsAsync: prodsAsync,
                        selectedCategoryId: selectedId,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  void _showProductDialog(BuildContext context, WidgetRef ref, Product? product, String? categoryId) {
    showDialog(
      context: context,
      builder: (_) => _ProductDialog(product: product, preselectedCategoryId: categoryId),
    );
  }
}

// ---------------------------------------------------------------------------
// Categories panel
// ---------------------------------------------------------------------------

class _CategoriesPanel extends ConsumerWidget {
  final AsyncValue<List<MenuCategory>> catsAsync;
  final String? selectedId;

  const _CategoriesPanel({required this.catsAsync, required this.selectedId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Text('Kategorien', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => _showCategoryDialog(context),
                  tooltip: 'Kategorie hinzufügen',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: catsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(e.toString())),
              data: (cats) => ListView.builder(
                itemCount: cats.length,
                itemBuilder: (_, i) {
                  final cat = cats[i];
                  final selected = cat.id == selectedId;
                  return ListTile(
                    selected: selected,
                    selectedTileColor: AppColors.primary.withAlpha(20),
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _parseColor(cat.color).withAlpha(38),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _categoryIcon(cat.icon),
                        size: 16,
                        color: _parseColor(cat.color),
                      ),
                    ),
                    title: Text(
                      cat.name,
                      style: TextStyle(
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () => ref.read(selectedCategoryIdProvider.notifier).state = cat.id,
                    trailing: selected
                        ? Icon(Icons.chevron_right, size: 16, color: AppColors.primary.withAlpha(153))
                        : null,
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCategoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _CategoryDialog(),
    );
  }
}

// ---------------------------------------------------------------------------
// Products panel
// ---------------------------------------------------------------------------

class _ProductsPanel extends ConsumerWidget {
  final AsyncValue<List<Product>> prodsAsync;
  final String? selectedCategoryId;

  const _ProductsPanel({required this.prodsAsync, required this.selectedCategoryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      child: prodsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (products) {
          if (selectedCategoryId == null) {
            return Center(
              child: Text('Kategorie auswählen', style: theme.textTheme.bodyLarge),
            );
          }
          if (products.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.restaurant_menu_outlined, size: 48, color: theme.colorScheme.outline),
                  const SizedBox(height: 8),
                  Text('Keine Produkte', style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Produkt hinzufügen'),
                    onPressed: () {},
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: products.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _ProductTile(
              product: products[i],
              onToggle: (val) => ref.read(apiClientProvider).updateProductAvailability(products[i].id, val),
              onEdit: () => showDialog(
                context: context,
                builder: (_) => _ProductDialog(
                  product: products[i],
                  preselectedCategoryId: selectedCategoryId,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  const _ProductTile({required this.product, required this.onToggle, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chf = 'CHF ${(product.price / 100).toStringAsFixed(2)}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: product.isAvailable
              ? AppColors.success.withAlpha(26)
              : Colors.grey.withAlpha(26),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.fastfood_outlined,
          color: product.isAvailable ? AppColors.success : Colors.grey,
          size: 20,
        ),
      ),
      title: Text(
        product.name,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: product.isAvailable ? null : Colors.grey,
        ),
      ),
      subtitle: Text(product.description, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(chf, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Switch(
            value: product.isAvailable,
            onChanged: onToggle,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: onEdit,
            tooltip: 'Bearbeiten',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

class _ProductDialog extends StatefulWidget {
  final Product? product;
  final String? preselectedCategoryId;

  const _ProductDialog({this.product, this.preselectedCategoryId});

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _price;
  String _taxGroup = 'reduced';
  bool _available = true;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.product?.name);
    _desc = TextEditingController(text: widget.product?.description);
    _price = TextEditingController(
      text: widget.product != null ? (widget.product!.price / 100).toStringAsFixed(2) : '',
    );
    _taxGroup = widget.product?.taxGroup ?? 'reduced';
    _available = widget.product?.isAvailable ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(isEdit ? 'Produkt bearbeiten' : 'Produkt hinzufügen',
                        style: theme.textTheme.titleLarge),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => v?.isEmpty == true ? 'Erforderlich' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _desc,
                  decoration: const InputDecoration(labelText: 'Beschreibung'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _price,
                  decoration: const InputDecoration(labelText: 'Preis (CHF)', prefixText: 'CHF '),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v?.isEmpty == true) return 'Erforderlich';
                    if (double.tryParse(v!.replaceAll(',', '.')) == null) return 'Ungültiger Preis';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _taxGroup,
                  decoration: const InputDecoration(labelText: 'Steuergruppe'),
                  items: const [
                    DropdownMenuItem(value: 'reduced', child: Text('Reduziert (3.8%)')),
                    DropdownMenuItem(value: 'standard', child: Text('Standard (8.1%)')),
                    DropdownMenuItem(value: 'accommodation', child: Text('Beherbergung (2.6%)')),
                    DropdownMenuItem(value: 'exempt', child: Text('Steuerbefreit (0%)')),
                  ],
                  onChanged: (v) => setState(() => _taxGroup = v ?? 'reduced'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Verfügbar'),
                  value: _available,
                  onChanged: (v) => setState(() => _available = v),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Abbrechen'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          // TODO: wire to API call
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(isEdit ? 'Gespeichert' : 'Hinzugefügt')),
                          );
                        }
                      },
                      child: Text(isEdit ? 'Speichern' : 'Hinzufügen'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog();

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('Kategorie hinzufügen', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Kategorie hinzugefügt')),
                      );
                    },
                    child: const Text('Hinzufügen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Color _parseColor(String hex) {
  try {
    return Color(int.parse(hex.replaceAll('#', '0xFF')));
  } catch (_) {
    return AppColors.primary;
  }
}

IconData _categoryIcon(String name) => switch (name) {
      'restaurant' || 'fastfood' => Icons.restaurant,
      'local_bar' || 'bar' => Icons.local_bar,
      'cake' || 'dessert' => Icons.cake,
      'soup_kitchen' => Icons.soup_kitchen,
      'coffee' || 'espresso' => Icons.coffee,
      'local_pizza' => Icons.local_pizza,
      _ => Icons.restaurant_menu,
    };
