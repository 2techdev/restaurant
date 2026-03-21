/// Waste / spoilage recording screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

class WasteScreen extends ConsumerStatefulWidget {
  const WasteScreen({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<WasteScreen> createState() => _WasteScreenState();
}

class _WasteScreenState extends ConsumerState<WasteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _reason = 'spoilage';
  bool _saving = false;

  static const _reasons = [
    'spoilage',
    'breakage',
    'theft',
    'expiry',
    'other',
  ];

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final itemAsync = ref.watch(inventoryItemDetailProvider(widget.itemId));

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainer,
        title: Text(
          l10n.invRecordWaste,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ),
      ),
      body: itemAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(e.toString(), style: const TextStyle(color: AppColors.red)),
        ),
        data: (item) {
          if (item == null) return const SizedBox.shrink();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Item info card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.delete_sweep_outlined,
                            color: AppColors.orange,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                '${l10n.invCurrentStock}: ${_fmtQty(item.quantity)} ${item.unit}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  _label(l10n.invQuantity),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: const TextStyle(color: AppColors.textDim),
                      suffixText: item.unit,
                      suffixStyle:
                          const TextStyle(color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.bgInput,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return '!';
                      if (n > item.quantity) return '> ${_fmtQty(item.quantity)}';
                      return null;
                    },
                  ),

                  const SizedBox(height: 20),

                  _label(l10n.invReason),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _reason,
                    dropdownColor: AppColors.surfaceContainer,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.bgInput,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    items: _reasons
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text(_reasonLabel(r, l10n)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _reason = v ?? 'spoilage'),
                  ),

                  const SizedBox(height: 20),

                  _label(l10n.invNotes),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _notesCtrl,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: l10n.invNotes,
                      hintStyle: const TextStyle(color: AppColors.textDim),
                      filled: true,
                      fillColor: AppColors.bgInput,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : () => _save(context),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.delete_sweep_outlined),
                      label: Text(
                        l10n.invRecordWaste,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _reasonLabel(String reason, AppLocalizations l10n) => switch (reason) {
        'spoilage' => l10n.invWasteSpoilage,
        'breakage' => l10n.invWasteBreakage,
        'theft' => l10n.invWasteTheft,
        'expiry' => l10n.invWasteExpiry,
        _ => l10n.invWasteOther,
      };

  Future<void> _save(BuildContext context) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final qty = double.parse(_qtyCtrl.text);
    final notes =
        '${_reasonLabel(_reason, AppLocalizations.of(context))}${_notesCtrl.text.trim().isNotEmpty ? ': ${_notesCtrl.text.trim()}' : ''}';
    final navigator = Navigator.of(context);

    final ok = await ref.read(inventoryActionsProvider.notifier).recordWaste(
          itemId: widget.itemId,
          quantity: qty,
          notes: notes,
        );
    if (mounted) {
      setState(() => _saving = false);
      if (ok) navigator.pop();
    }
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      );

  String _fmtQty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
