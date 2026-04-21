/// Full-screen product add/edit form.
///
/// Sections:
///   1. Basic Info    — name, description, category, image placeholder, button color
///   2. Price/Variants — specifications/SKU list, weight-based, open-price toggles
///   3. Tax            — Swiss MWST group selector with auto-filled dine-in/takeaway rates
///   4. Modifiers      — link existing modifier groups to this product
///   5. Combo          — set-menu composition
///   6. Additional     — printer group, prep time, barcode, stock status, display order, active
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/modifier_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_specification_entity.dart';
import 'package:gastrocore_pos/shared/widgets/pos_text_field.dart';
import 'package:gastrocore_pos/shared/widgets/pos_button.dart';

// ---------------------------------------------------------------------------
// Internal form state models
// ---------------------------------------------------------------------------

/// A single specification / SKU variant row in the price section.
class _SpecRow {
  String name;
  TextEditingController priceController;
  bool isDefault;

  _SpecRow({
    required this.name,
    required String priceText,
    this.isDefault = false,
  }) : priceController = TextEditingController(text: priceText);

  void dispose() => priceController.dispose();
}

/// A combo item entry.
// ignore: unused_element_parameter
class _ComboItemRow {
  String productId;
  String productName;
  int quantity;
  String? groupName;
  bool canSubstitute;

  _ComboItemRow({
    required this.productId,
    required this.productName,
    // ignore: unused_element_parameter
    this.quantity = 1,
    // ignore: unused_element_parameter
    this.groupName,
    // ignore: unused_element_parameter
    this.canSubstitute = false,
  });
}

// ---------------------------------------------------------------------------
// Swiss MWST tax rates
// ---------------------------------------------------------------------------

/// Swiss MWST rates per tax group and service type.
///
/// 2.6% – reduced rate (food/beverage takeaway)
/// 3.8% – special rate (accommodation / Beherbergung)
/// 8.1% – standard rate (dine-in, alcohol, default)
const _taxRates = <String, Map<String, Map<String, double>>>{
  'CH': {
    'food': {'dine_in': 8.1, 'takeaway': 2.6},
    'beverage': {'dine_in': 8.1, 'takeaway': 2.6},
    'alcohol': {'dine_in': 8.1, 'takeaway': 8.1},
    'accommodation': {'dine_in': 3.8, 'takeaway': 3.8},
    'custom': {'dine_in': 8.1, 'takeaway': 8.1},
  },
  'DE': {
    'food': {'dine_in': 7.0, 'takeaway': 7.0},
    'beverage': {'dine_in': 19.0, 'takeaway': 19.0},
    'alcohol': {'dine_in': 19.0, 'takeaway': 19.0},
    'accommodation': {'dine_in': 7.0, 'takeaway': 7.0},
    'custom': {'dine_in': 19.0, 'takeaway': 19.0},
  },
};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _buttonColors = [
  '#FF9F0A', '#FF3B30', '#FF6B6B', '#BF5AF2', '#528DFF', '#05B046',
];

const _printerGroups = ['kitchen', 'bar', 'dessert', 'no_print'];
const _stockStatuses = ['in_stock', 'out_of_stock', 'out_of_stock_today', 'delisted'];
const _taxGroupOptions = ['food', 'beverage', 'alcohol', 'accommodation', 'custom'];

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

/// Shows a full-screen dialog for adding or editing a product.
///
/// Returns `true` if the product was saved, `null`/`false` otherwise.
Future<bool?> showProductFormDialog(
  BuildContext context, {
  ProductEntity? existing,
  required String initialCategoryId,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierColor: AppColors.bgOverlay,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: (ctx, anim, anim2, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      );
    },
    pageBuilder: (ctx, anim, anim2) => _ProductFormPage(
      existing: existing,
      initialCategoryId: initialCategoryId,
    ),
  );
}

// ---------------------------------------------------------------------------
// _ProductFormPage
// ---------------------------------------------------------------------------

class _ProductFormPage extends ConsumerStatefulWidget {
  final ProductEntity? existing;
  final String initialCategoryId;

  const _ProductFormPage({
    this.existing,
    required this.initialCategoryId,
  });

  @override
  ConsumerState<_ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends ConsumerState<_ProductFormPage> {
  bool get _isEditing => widget.existing != null;

  // Section 1 – Basic Info
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late String _categoryId;
  String? _imagePath;
  String _buttonColor = _buttonColors.first;
  late final TextEditingController _customHexCtrl;

  // Section 2 – Price / Specs
  final List<_SpecRow> _specs = [];
  bool _isWeighProduct = false;
  bool _isOpenPrice = false;

  // Section 3 – Tax
  String _taxGroup = 'food';
  bool _taxInclusive = true;
  final String _countryCode = 'CH';

  // Section 4 – Modifiers
  List<ModifierGroupEntity> _linkedModifierGroups = [];

  // Section 5 – Combo
  bool _isCombo = false;
  late final TextEditingController _comboPriceCtrl;
  final List<_ComboItemRow> _comboItems = [];

  // Section 6 – Additional
  String _printerGroup = 'kitchen';
  late final TextEditingController _prepTimeCtrl;
  late final TextEditingController _barcodeCtrl;
  String _stockStatus = 'in_stock';
  late final TextEditingController _displayOrderCtrl;
  bool _isActive = true;

  /// Sold-out / 86'd flag. Default true = sellable. When the operator flips
  /// this off the product stays listed on the menu but the POS grid greys
  /// it out and blocks taps.
  bool _isAvailable = true;

  // Cached async data
  List<CategoryEntity> _categories = [];
  List<ProductEntity> _allProducts = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;

    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _categoryId = e?.categoryId ?? widget.initialCategoryId;
    _imagePath = e?.imagePath;
    _customHexCtrl = TextEditingController();

    // Default spec row – replaced by DB specs when editing (see _loadData)
    if (e != null) {
      _specs.add(_SpecRow(
        name: 'Default',
        priceText: (e.price / 100).toStringAsFixed(2),
        isDefault: true,
      ));
    } else {
      _specs.add(_SpecRow(name: 'Default', priceText: '', isDefault: true));
    }

    _isWeighProduct = e?.isWeightBased ?? false;
    _isOpenPrice = e?.isOpenPrice ?? false;

    _taxGroup = (e?.taxGroup != null && _taxGroupOptions.contains(e!.taxGroup))
        ? e.taxGroup
        : 'food';
    _taxInclusive = true;

    _linkedModifierGroups = List.from(e?.modifierGroups ?? []);

    _comboPriceCtrl = TextEditingController();
    _prepTimeCtrl = TextEditingController(
        text: e?.prepTimeMinutes?.toString() ?? '');
    _barcodeCtrl = TextEditingController(text: e?.barcode ?? '');
    _stockStatus = e?.stockStatus ?? 'in_stock';
    _displayOrderCtrl =
        TextEditingController(text: e?.displayOrder.toString() ?? '0');
    _isActive = e?.isActive ?? true;
    _isAvailable = e?.isAvailable ?? true;

    _loadData();
  }

  Future<void> _loadData() async {
    final repo = ref.read(menuRepositoryProvider);
    final cats = await ref.read(categoriesProvider.future);
    final prods = await ref.read(productsProvider.future);

    // Load saved specs when editing so users see saved variants
    List<ProductSpecificationEntity> savedSpecs = [];
    if (widget.existing != null) {
      savedSpecs = await repo.getProductSpecifications(widget.existing!.id);
    }

    if (!mounted) return;
    setState(() {
      _categories = cats;
      _allProducts = prods;

      if (savedSpecs.isNotEmpty) {
        for (final s in _specs) {
          s.dispose();
        }
        _specs.clear();
        for (final s in savedSpecs) {
          _specs.add(_SpecRow(
            name: s.name,
            priceText: (s.price / 100).toStringAsFixed(2),
            isDefault: s.isDefault,
          ));
        }
      }

      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _comboPriceCtrl.dispose();
    _prepTimeCtrl.dispose();
    _barcodeCtrl.dispose();
    _displayOrderCtrl.dispose();
    _customHexCtrl.dispose();
    for (final s in _specs) {
      s.dispose();
    }
    super.dispose();
  }

  // =========================================================================
  // Image picker
  // =========================================================================

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              if (_imagePath != null)
                ListTile(
                  leading: const Icon(Icons.delete_rounded, color: Colors.red),
                  title: const Text('Remove image',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    setState(() => _imagePath = null);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      );
      if (source == null) return;
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 800,
      );
      if (picked != null && mounted) {
        setState(() => _imagePath = picked.path);
      }
    } catch (_) {
      // Permission denied or picker unavailable — fail silently.
    }
  }

  // =========================================================================
  // Build
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSection1BasicInfo(),
                              const SizedBox(height: 8),
                              _buildSection2Price(),
                              const SizedBox(height: 8),
                              _buildSection3Tax(),
                              const SizedBox(height: 8),
                              _buildSection4Modifiers(),
                              const SizedBox(height: 8),
                              _buildSection5Combo(),
                              const SizedBox(height: 8),
                              _buildSection6Additional(),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Top / bottom bars
  // =========================================================================

  Widget _buildTopBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: AppColors.surface,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.close_rounded,
                  size: 22, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _isEditing ? 'Edit Product' : 'New Product',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (_isEditing)
            Text(
              'ID: ${widget.existing!.id.substring(0, 8)}…',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textDim,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      color: AppColors.surface,
      child: Row(
        children: [
          Expanded(
            child: PosGhostButton(
              label: 'Cancel',
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: PosGradientButton(
              label: _isEditing ? 'Update' : 'Save',
              icon: Icons.save_rounded,
              height: 48,
              isLoading: _isSaving,
              onPressed: _isSaving ? null : _handleSave,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Section helpers
  // =========================================================================

  Widget _sectionHeader(String title, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  // =========================================================================
  // Section 1 – Basic Info
  // =========================================================================

  Widget _buildSection1BasicInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Basic Info', Icons.info_outline_rounded),
        _sectionCard(
          children: [
            PosTextField(
              label: '* Product Name',
              hint: 'e.g. Adana Kebab',
              controller: _nameCtrl,
              autofocus: !_isEditing,
            ),
            const SizedBox(height: 16),
            PosTextField(
              label: 'Description',
              hint: 'Product description (optional)',
              controller: _descCtrl,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            _buildLabel('* Category'),
            const SizedBox(height: 8),
            _buildDropdown<String>(
              value: _categoryId.isEmpty && _categories.isNotEmpty
                  ? _categories.first.id
                  : _categoryId,
              items: _categories
                  .map((c) =>
                      DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _categoryId = v);
              },
            ),
            const SizedBox(height: 16),
            _buildLabel('Image'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.bgInput,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _imagePath != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_imagePath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_rounded,
                            size: 40,
                            color: AppColors.textDim,
                          ),
                        ),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_rounded,
                              size: 28, color: AppColors.textDim),
                          SizedBox(height: 4),
                          Text(
                            '+ Add',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textDim,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            _buildLabel('Button Color'),
            const SizedBox(height: 8),
            Row(
              children: [
                ..._buttonColors.map((hex) {
                  final isSelected = _buttonColor == hex;
                  final color = _hexToColor(hex);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _buttonColor = hex),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(
                                  color: AppColors.textPrimary, width: 2.5)
                              : null,
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: PosTextField(
                    hint: '#HEX',
                    controller: _customHexCtrl,
                    onSubmitted: (v) {
                      if (v.isNotEmpty) {
                        final hex = v.startsWith('#') ? v : '#$v';
                        setState(() => _buttonColor = hex);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // =========================================================================
  // Section 2 – Price / Variants
  // =========================================================================

  Widget _buildSection2Price() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Price & Variants', Icons.attach_money_rounded),
        _sectionCard(
          children: [
            _buildLabel('* Specifications / SKU List'),
            const SizedBox(height: 4),
            const Text(
              'Add size variants (e.g. Small / Medium / Large). The default variant '
              'price is used as the product\'s base price.',
              style: TextStyle(fontSize: 11, color: AppColors.textDim, height: 1.5),
            ),
            const SizedBox(height: 12),
            ...List.generate(_specs.length, _buildSpecRow),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _addSpecRow,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.accentDim,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text(
                      '+ Add Variant',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildToggleRow(
              'Weight-based Product',
              'Sold by weight measurement',
              _isWeighProduct,
              (v) => setState(() => _isWeighProduct = v),
            ),
            const SizedBox(height: 12),
            _buildToggleRow(
              'Open Price',
              'Allows manual price entry at POS',
              _isOpenPrice,
              (v) => setState(() => _isOpenPrice = v),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSpecRow(int index) {
    final spec = _specs[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bgInput,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.drag_handle_rounded,
                size: 18, color: AppColors.textDim),
            const SizedBox(width: 8),

            // Name field (read-only when it's the only row)
            Expanded(
              flex: 3,
              child: index == 0 && _specs.length == 1
                  ? Text(
                      spec.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    )
                  : SizedBox(
                      height: 36,
                      child: TextField(
                        controller: TextEditingController(text: spec.name),
                        onChanged: (v) => spec.name = v,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Name (e.g. Small)',
                          hintStyle:
                              TextStyle(color: AppColors.textDim, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 8),
                          isDense: true,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8),

            // Price field
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: spec.priceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    hintStyle:
                        TextStyle(color: AppColors.textDim, fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                    prefixText: 'CHF ',
                    prefixStyle: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Default radio
            GestureDetector(
              onTap: () {
                setState(() {
                  for (int j = 0; j < _specs.length; j++) {
                    _specs[j].isDefault = j == index;
                  }
                });
              },
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: spec.isDefault
                      ? AppColors.primary
                      : Colors.transparent,
                  border: Border.all(
                    color:
                        spec.isDefault ? AppColors.primary : AppColors.textDim,
                    width: 2,
                  ),
                ),
                child: spec.isDefault
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 8),

            // Delete (not shown for single default row)
            if (_specs.length > 1)
              GestureDetector(
                onTap: () => _removeSpecRow(index),
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(Icons.close_rounded,
                      size: 16, color: AppColors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _addSpecRow() {
    setState(() {
      _specs.add(_SpecRow(name: '', priceText: '', isDefault: false));
    });
  }

  void _removeSpecRow(int index) {
    final wasDefault = _specs[index].isDefault;
    setState(() {
      _specs[index].dispose();
      _specs.removeAt(index);
      if (wasDefault && _specs.isNotEmpty) {
        _specs[0].isDefault = true;
      }
    });
  }

  // =========================================================================
  // Section 3 – Tax
  // =========================================================================

  Widget _buildSection3Tax() {
    final dineInRate =
        _taxRates[_countryCode]?[_taxGroup]?['dine_in'] ?? 8.1;
    final takeawayRate =
        _taxRates[_countryCode]?[_taxGroup]?['takeaway'] ?? 2.6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Tax (Swiss MWST)', Icons.receipt_long_rounded),
        _sectionCard(
          children: [
            _buildLabel('Tax Group'),
            const SizedBox(height: 4),
            const Text(
              'CH MWST: 2.6% reduced · 3.8% accommodation · 8.1% standard',
              style: TextStyle(fontSize: 11, color: AppColors.textDim),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _taxGroupOptions.map((tg) {
                final isSelected = _taxGroup == tg;
                return GestureDetector(
                  onTap: () => setState(() => _taxGroup = tg),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.accentDim
                          : AppColors.bgInput,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _taxGroupLabel(tg),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                    child: _buildTaxRateDisplay('Dine-In VAT', dineInRate)),
                const SizedBox(width: 16),
                Expanded(
                    child:
                        _buildTaxRateDisplay('Takeaway VAT', takeawayRate)),
              ],
            ),
            const SizedBox(height: 16),
            _buildToggleRow(
              'Tax Inclusive',
              'Prices are shown inclusive of VAT',
              _taxInclusive,
              (v) => setState(() => _taxInclusive = v),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTaxRateDisplay(String label, double rate) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textDim,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${rate.toStringAsFixed(1)}%',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  String _taxGroupLabel(String tg) {
    switch (tg) {
      case 'food':
        return 'Food';
      case 'beverage':
        return 'Beverage';
      case 'alcohol':
        return 'Alcohol';
      case 'accommodation':
        return 'Accommodation (3.8%)';
      case 'custom':
        return 'Custom';
      default:
        return tg;
    }
  }

  // =========================================================================
  // Section 4 – Modifiers / Add-ons
  // =========================================================================

  Widget _buildSection4Modifiers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Modifiers & Add-ons', Icons.tune_rounded),
        _sectionCard(
          children: [
            if (_linkedModifierGroups.isNotEmpty) ...[
              ...List.generate(
                _linkedModifierGroups.length,
                (i) => _buildModifierGroupChip(_linkedModifierGroups[i], i),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _showModifierGroupSelector,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.accentDim,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded,
                              size: 18, color: AppColors.primary),
                          SizedBox(width: 6),
                          Text(
                            '+ Link Modifier Group',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_linkedModifierGroups.isEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Modifier groups allow customers to customise this product. '
                'Examples: Size (Small / Medium / Large), Extras (cheese +CHF 2, bacon +CHF 1.50), '
                'Sauce (no extra charge).',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textDim,
                  height: 1.6,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildModifierGroupChip(ModifierGroupEntity group, int index) {
    final isFree = group.modifiers.every((m) => m.priceDelta == 0);
    final typeLabel = isFree ? 'Modifier' : 'Add-on';
    final typeColor = isFree ? AppColors.primary : AppColors.purple;
    final typeBg = isFree ? AppColors.accentDim : AppColors.purpleDim;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: typeBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              typeLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: typeColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (group.modifiers.isNotEmpty)
                  Text(
                    group.modifiers.map((m) {
                      final delta = m.priceDelta > 0
                          ? ' +CHF ${(m.priceDelta / 100).toStringAsFixed(2)}'
                          : '';
                      return '${m.name}$delta';
                    }).join(', '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDim,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() => _linkedModifierGroups.removeAt(index));
            },
            child: const SizedBox(
              width: 28,
              height: 28,
              child: Icon(Icons.close_rounded,
                  size: 16, color: AppColors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showModifierGroupSelector() async {
    final allGroups =
        await ref.read(allModifierGroupsProvider.future).catchError((_) => <ModifierGroupEntity>[]);
    if (!mounted) return;

    final linkedIds = _linkedModifierGroups.map((g) => g.id).toSet();
    final selected = await showDialog<Set<String>>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (ctx) => _ModifierGroupSelectorDialog(
        allGroups: allGroups,
        initiallySelected: linkedIds,
      ),
    );

    if (selected != null) {
      setState(() {
        _linkedModifierGroups = allGroups
            .where((g) => selected.contains(g.id))
            .toList();
      });
    }
  }

  // =========================================================================
  // Section 5 – Combo / Set Menu
  // =========================================================================

  Widget _buildSection5Combo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Combo / Set Menu', Icons.restaurant_menu_rounded),
        _sectionCard(
          children: [
            _buildToggleRow(
              'Combo / Set Menu',
              'This product is a combo or set menu',
              _isCombo,
              (v) => setState(() => _isCombo = v),
            ),
            if (_isCombo) ...[
              const SizedBox(height: 16),
              PosTextField(
                label: 'Combo Price (CHF)',
                hint: '0.00',
                controller: _comboPriceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              _buildLabel('Combo Contents'),
              const SizedBox(height: 8),
              if (_comboItems.isNotEmpty)
                ...List.generate(_comboItems.length, _buildComboItemRow),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showComboProductSelector,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.accentDim,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded,
                          size: 18, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text(
                        '+ Add Product',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Fixed items: Leave group name empty.\n'
                'Substitutable items: Enter a group name (e.g. "Drink choice").',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textDim,
                  height: 1.6,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildComboItemRow(int index) {
    final item = _comboItems[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _miniButton(Icons.remove_rounded, () {
                      if (item.quantity > 1) {
                        setState(() => item.quantity--);
                      }
                    }),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${item.quantity}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    _miniButton(Icons.add_rounded, () {
                      setState(() => item.quantity++);
                    }),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () =>
                    setState(() => _comboItems.removeAt(index)),
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(Icons.close_rounded,
                      size: 16, color: AppColors.red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller:
                        TextEditingController(text: item.groupName ?? ''),
                    onChanged: (v) =>
                        item.groupName = v.isEmpty ? null : v,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Group name (empty = fixed)',
                      hintStyle: TextStyle(
                          color: AppColors.textDim, fontSize: 11),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Substitutable',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textDim,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 24,
                    child: Switch(
                      value: item.canSubstitute,
                      activeThumbColor: AppColors.green,
                      inactiveTrackColor: AppColors.surfaceContainerHigh,
                      onChanged: (v) =>
                          setState(() => item.canSubstitute = v),
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showComboProductSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        String search = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = _allProducts.where((p) {
              if (search.isEmpty) return true;
              return p.name.toLowerCase().contains(search.toLowerCase());
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.85,
              expand: false,
              builder: (ctx, scrollController) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: PosTextField(
                      hint: 'Search products…',
                      prefixIcon: Icons.search_rounded,
                      autofocus: true,
                      onChanged: (v) =>
                          setSheetState(() => search = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final p = filtered[i];
                        return ListTile(
                          title: Text(p.name,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                          subtitle: Text(
                              'CHF ${(p.price / 100).toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: AppColors.textDim, fontSize: 12)),
                          onTap: () {
                            Navigator.pop(ctx);
                            setState(() {
                              _comboItems.add(_ComboItemRow(
                                productId: p.id,
                                productName: p.name,
                              ));
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _miniButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(icon, size: 16, color: AppColors.textSecondary),
      ),
    );
  }

  // =========================================================================
  // Section 6 – Additional
  // =========================================================================

  Widget _buildSection6Additional() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Additional Settings', Icons.settings_rounded),
        _sectionCard(
          children: [
            _buildLabel('Printer Group'),
            const SizedBox(height: 8),
            _buildDropdown<String>(
              value: _printerGroup,
              items: _printerGroups
                  .map((pg) => DropdownMenuItem(
                        value: pg,
                        child: Text(_printerGroupLabel(pg)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _printerGroup = v);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PosTextField(
                    label: 'Prep Time (min)',
                    hint: '0',
                    controller: _prepTimeCtrl,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: PosTextField(
                    label: 'Barcode (EAN/UPC)',
                    hint: 'Scan or enter barcode',
                    controller: _barcodeCtrl,
                    prefixIcon: Icons.qr_code_scanner_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildLabel('Stock Status'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _stockStatuses.map((ss) {
                final isSelected = _stockStatus == ss;
                return GestureDetector(
                  onTap: () => setState(() => _stockStatus = ss),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _stockStatusColor(ss).withValues(alpha: 0.15)
                          : AppColors.bgInput,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _stockStatusLabel(ss),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? _stockStatusColor(ss)
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PosTextField(
                    label: 'Display Order',
                    hint: '0',
                    controller: _displayOrderCtrl,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 16),
            _buildToggleRow(
              'Active',
              'Product is visible on POS',
              _isActive,
              (v) => setState(() => _isActive = v),
            ),
            const SizedBox(height: 12),
            // Sold-out / 86'd toggle. Labels are Turkish because this is an
            // operator-facing control the pilot asked for in Turkish ("Satışta"
            // / "Satışta Değil"). The toggle value is the positive form so
            // "on = sellable", matching every other toggle's ON-means-enabled
            // convention and mapping 1:1 to the DB default of true.
            _buildToggleRow(
              'Satışta',
              'Kapalıysa ürün POS ızgarasında gri görünür ve siparişe alınamaz',
              _isAvailable,
              (v) => setState(() => _isAvailable = v),
            ),
          ],
        ),
      ],
    );
  }

  String _printerGroupLabel(String pg) {
    switch (pg) {
      case 'kitchen':
        return 'Kitchen';
      case 'bar':
        return 'Bar';
      case 'dessert':
        return 'Dessert';
      case 'no_print':
        return 'No Print';
      default:
        return pg;
    }
  }

  String _stockStatusLabel(String ss) {
    switch (ss) {
      case 'in_stock':
        return 'In Stock';
      case 'out_of_stock':
        return 'Out of Stock';
      case 'out_of_stock_today':
        return 'Out Today';
      case 'delisted':
        return 'Delisted';
      default:
        return ss;
    }
  }

  Color _stockStatusColor(String ss) {
    switch (ss) {
      case 'in_stock':
        return AppColors.green;
      case 'out_of_stock':
        return AppColors.red;
      case 'out_of_stock_today':
        return AppColors.orange;
      case 'delisted':
        return AppColors.textDim;
      default:
        return AppColors.textSecondary;
    }
  }

  // =========================================================================
  // Common helpers
  // =========================================================================

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: AppColors.surfaceContainerHighest,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textDim),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildToggleRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textDim,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: AppColors.green,
          inactiveTrackColor: AppColors.surfaceContainerHigh,
          onChanged: onChanged,
        ),
      ],
    );
  }

  // =========================================================================
  // Save handler
  // =========================================================================

  Future<void> _handleSave() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError('Product name is required.');
      return;
    }

    final defaultSpec =
        _specs.firstWhere((s) => s.isDefault, orElse: () => _specs.first);
    final priceInCents =
        ((double.tryParse(defaultSpec.priceController.text.replaceAll(',', '.')) ?? 0) * 100)
            .round();

    if (priceInCents <= 0 && !_isOpenPrice) {
      _showError('Please enter a price.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final repo = ref.read(menuRepositoryProvider);
      final tenantId = ref.read(tenantIdProvider);

      late final String productId;

      if (_isEditing) {
        productId = widget.existing!.id;
        await repo.updateProduct(widget.existing!.copyWith(
          name: name,
          price: priceInCents,
          categoryId: _categoryId,
          imagePath: () => _imagePath,
          description: () =>
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          taxGroup: _taxGroup,
          isActive: _isActive,
          isAvailable: _isAvailable,
          printerGroup: _printerGroup,
          barcode: () =>
              _barcodeCtrl.text.trim().isEmpty
                  ? null
                  : _barcodeCtrl.text.trim(),
          prepTimeMinutes: () {
            final v = int.tryParse(_prepTimeCtrl.text);
            return v != null && v > 0 ? v : null;
          },
          displayOrder: int.tryParse(_displayOrderCtrl.text) ?? 0,
          stockStatus: _stockStatus,
          isOpenPrice: _isOpenPrice,
          isWeightBased: _isWeighProduct,
        ));
      } else {
        final newProduct = ProductEntity(
          id: IdGenerator.generateId(),
          tenantId: tenantId,
          categoryId: _categoryId,
          name: name,
          price: priceInCents,
          costPrice: 0,
          taxGroup: _taxGroup,
          isActive: _isActive,
          isAvailable: _isAvailable,
          displayOrder: int.tryParse(_displayOrderCtrl.text) ?? 0,
          printerGroup: _printerGroup,
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          barcode: _barcodeCtrl.text.trim().isEmpty
              ? null
              : _barcodeCtrl.text.trim(),
          imagePath: _imagePath,
          prepTimeMinutes: int.tryParse(_prepTimeCtrl.text),
          stockStatus: _stockStatus,
          isOpenPrice: _isOpenPrice,
          isWeightBased: _isWeighProduct,
        );
        await repo.createProduct(newProduct);
        productId = newProduct.id;
      }

      // Persist variant specs to product_specifications table
      if (_specs.isNotEmpty) {
        final specEntities = <ProductSpecificationEntity>[];
        for (var i = 0; i < _specs.length; i++) {
          final s = _specs[i];
          final p = ((double.tryParse(
                          s.priceController.text.replaceAll(',', '.')) ??
                      0) *
                  100)
              .round();
          specEntities.add(ProductSpecificationEntity(
            id: IdGenerator.generateId(),
            tenantId: tenantId,
            productId: productId,
            name: s.name.isEmpty ? 'Default' : s.name,
            price: p,
            isDefault: s.isDefault,
            displayOrder: i,
          ));
        }
        await repo.saveProductSpecifications(productId, tenantId, specEntities);
      }

      // Sync modifier group links
      final currentlyLinked =
          await repo.getModifierGroupsForProduct(productId);
      final currentIds = currentlyLinked.map((g) => g.id).toSet();
      final desiredIds = _linkedModifierGroups.map((g) => g.id).toSet();

      // Link new groups
      for (var i = 0; i < _linkedModifierGroups.length; i++) {
        await repo.linkModifierGroupToProduct(
            productId, _linkedModifierGroups[i].id, i);
      }
      // Unlink removed groups
      for (final id in currentIds.difference(desiredIds)) {
        await repo.unlinkModifierGroupFromProduct(productId, id);
      }

      ref.invalidate(productsProvider);
      ref.invalidate(adminProductsProvider);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static Color _hexToColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('FF');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}

// ---------------------------------------------------------------------------
// Modifier group selector dialog
// ---------------------------------------------------------------------------

class _ModifierGroupSelectorDialog extends StatefulWidget {
  final List<ModifierGroupEntity> allGroups;
  final Set<String> initiallySelected;

  const _ModifierGroupSelectorDialog({
    required this.allGroups,
    required this.initiallySelected,
  });

  @override
  State<_ModifierGroupSelectorDialog> createState() =>
      _ModifierGroupSelectorDialogState();
}

class _ModifierGroupSelectorDialogState
    extends State<_ModifierGroupSelectorDialog> {
  late final Set<String> _selected;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initiallySelected);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.allGroups.where((g) {
      if (_search.isEmpty) return true;
      return g.name.toLowerCase().contains(_search.toLowerCase());
    }).toList();

    return Dialog(
      backgroundColor: AppColors.surfaceContainerHighest,
      elevation: 0,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Link Modifier Groups',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Select modifier groups to attach to this product.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  PosTextField(
                    hint: 'Search modifier groups…',
                    prefixIcon: Icons.search_rounded,
                    autofocus: true,
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ],
              ),
            ),

            Flexible(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No modifier groups found.\nCreate some in the Modifiers tab first.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final group = filtered[i];
                        final isChecked = _selected.contains(group.id);
                        return Material(
                          color: isChecked
                              ? AppColors.accentDim
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (isChecked) {
                                  _selected.remove(group.id);
                                } else {
                                  _selected.add(group.id);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  // Checkbox indicator
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: isChecked
                                          ? AppColors.primary
                                          : Colors.transparent,
                                      borderRadius:
                                          BorderRadius.circular(5),
                                      border: Border.all(
                                        color: isChecked
                                            ? AppColors.primary
                                            : AppColors.textDim,
                                        width: 2,
                                      ),
                                    ),
                                    child: isChecked
                                        ? const Icon(Icons.check_rounded,
                                            size: 13, color: Colors.white)
                                        : null,
                                  ),
                                  const SizedBox(width: 12),

                                  // Name + meta
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          group.name,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: isChecked
                                                ? AppColors.primary
                                                : AppColors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          '${group.modifiers.length} option${group.modifiers.length == 1 ? '' : 's'}'
                                          ' · ${group.selectionType == ModifierSelectionType.single ? 'Single' : 'Multiple'}'
                                          '${group.isRequired ? ' · Required' : ''}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textDim,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: PosGhostButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PosGradientButton(
                      label: 'Confirm (${_selected.length})',
                      height: 44,
                      onPressed: () => Navigator.pop(context, _selected),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
