import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';

/// Read-only overlay shown in product detail / edit screens.
///
/// Surfaces the four fields that come from the Gastro Hub admin panel
/// (cloud Postgres → menu_sync → POS Drift):
///   • High-res image preview
///   • Long-form online description
///   • Allergen breakdown (contains / mayContain / freeFrom)
///   • "Online'da popüler" badge
///
/// All fields are read-only — every input carries an explanatory tooltip
/// pointing the operator at gastro.2hub.ch for edits. The overlay never
/// mutates any state; it just decodes [ProductEntity.allergenInfo] (a JSON
/// blob mirroring the cloud Postgres JSONB column) and renders the result.
///
/// Designed to be embedded as either:
///   • A tab in a TabBarView ([LinkedItemsOverlayTab]), or
///   • A bottom-sheet via [showLinkedItemsOverlaySheet].
class LinkedItemsOverlayTab extends StatelessWidget {
  const LinkedItemsOverlayTab({super.key, required this.product});

  final ProductEntity product;

  @override
  Widget build(BuildContext context) {
    final allergens = _decodeAllergens(product.allergenInfo);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Banner(),
          const SizedBox(height: 16),
          if (product.isPopularOnline) const _PopularBadge(),
          if (product.isPopularOnline) const SizedBox(height: 16),
          _ImagePreview(imagePath: product.imagePath),
          const SizedBox(height: 16),
          _Section(
            label: 'Uzun açıklama',
            tooltip: _kReadOnlyTooltip,
            child: Text(
              (product.description ?? '').trim().isEmpty
                  ? '— (online açıklama yok)'
                  : product.description!,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          _AllergenPanel(data: allergens),
        ],
      ),
    );
  }

  static const _kReadOnlyTooltip =
      'Bu alanlar Gastro Hub admin\'inde yönetilir (gastro.2hub.ch).';

  static _AllergenData _decodeAllergens(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const _AllergenData.empty();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const _AllergenData.empty();
      List<String> pick(String key) {
        final v = json[key];
        if (v is! List) return const [];
        return v.whereType<String>().toList(growable: false);
      }
      return _AllergenData(
        contains: pick('contains'),
        mayContain: pick('mayContain'),
        freeFrom: pick('freeFrom'),
      );
    } catch (_) {
      return const _AllergenData.empty();
    }
  }
}

/// Bottom-sheet variant — useful when the host screen has no spare tab slot.
Future<void> showLinkedItemsOverlaySheet(
  BuildContext context,
  ProductEntity product,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        child: LinkedItemsOverlayTab(product: product),
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Bu sekme salt-okunurdur. Düzenlemek için Gastro Hub admin panelini kullanın (gastro.2hub.ch).',
              style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }
}

class _PopularBadge extends StatelessWidget {
  const _PopularBadge();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: LinkedItemsOverlayTab._kReadOnlyTooltip,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.amber.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.amber.shade400),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star, color: Colors.amber.shade700, size: 16),
              const SizedBox(width: 6),
              const Text(
                "Online'da popüler",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.imagePath});

  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final src = imagePath;
    return Tooltip(
      message: LinkedItemsOverlayTab._kReadOnlyTooltip,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: src == null || src.isEmpty
              ? Container(
                  color: Colors.grey.shade200,
                  child: const Center(
                    child: Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
                  ),
                )
              : src.startsWith('http')
                  ? Image.network(
                      src,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image, size: 48),
                      ),
                    )
                  : Image.asset(src, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.tooltip, required this.child});

  final String label;
  final String tooltip;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: tooltip,
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.lock_outline, size: 12, color: Colors.grey.shade500),
            ],
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _AllergenPanel extends StatelessWidget {
  const _AllergenPanel({required this.data});

  final _AllergenData data;

  @override
  Widget build(BuildContext context) {
    return _Section(
      label: 'Alerjen bilgisi',
      tooltip: LinkedItemsOverlayTab._kReadOnlyTooltip,
      child: data.isEmpty
          ? const Text(
              '— (online alerjen bilgisi yok)',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.contains.isNotEmpty)
                  _AllergenRow(
                    title: 'İçerir',
                    items: data.contains,
                    color: Colors.red.shade100,
                    border: Colors.red.shade300,
                  ),
                if (data.mayContain.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _AllergenRow(
                    title: 'İçerebilir',
                    items: data.mayContain,
                    color: Colors.orange.shade100,
                    border: Colors.orange.shade300,
                  ),
                ],
                if (data.freeFrom.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _AllergenRow(
                    title: 'İçermez',
                    items: data.freeFrom,
                    color: Colors.green.shade100,
                    border: Colors.green.shade300,
                  ),
                ],
              ],
            ),
    );
  }
}

class _AllergenRow extends StatelessWidget {
  const _AllergenRow({
    required this.title,
    required this.items,
    required this.color,
    required this.border,
  });

  final String title;
  final List<String> items;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items
                .map(
                  (a) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: border),
                    ),
                    child: Text(
                      a,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _AllergenData {
  const _AllergenData({
    required this.contains,
    required this.mayContain,
    required this.freeFrom,
  });

  const _AllergenData.empty()
      : contains = const [],
        mayContain = const [],
        freeFrom = const [];

  final List<String> contains;
  final List<String> mayContain;
  final List<String> freeFrom;

  bool get isEmpty =>
      contains.isEmpty && mayContain.isEmpty && freeFrom.isEmpty;
}
