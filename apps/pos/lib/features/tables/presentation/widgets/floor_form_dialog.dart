/// Dialog for creating or editing a floor / zone.
///
/// Zones represent physical areas of the restaurant
/// (e.g. "Main Hall", "Terrace", "Bar").
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';

/// Shows the [FloorFormDialog] as a modal dialog.
///
/// Pass [existing] to edit; omit to create a new floor.
/// [nextDisplayOrder] is used as the default order value when creating.
Future<void> showFloorFormDialog(
  BuildContext context, {
  FloorEntity? existing,
  int nextDisplayOrder = 0,
}) {
  return showDialog(
    context: context,
    builder: (_) => FloorFormDialog(
      existing: existing,
      nextDisplayOrder: nextDisplayOrder,
    ),
  );
}

class FloorFormDialog extends ConsumerStatefulWidget {
  final FloorEntity? existing;
  final int nextDisplayOrder;

  const FloorFormDialog({
    super.key,
    this.existing,
    this.nextDisplayOrder = 0,
  });

  @override
  ConsumerState<FloorFormDialog> createState() => _FloorFormDialogState();
}

class _FloorFormDialogState extends ConsumerState<FloorFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _orderCtrl;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _orderCtrl = TextEditingController(
      text: (e?.displayOrder ?? widget.nextDisplayOrder).toString(),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final notifier = ref.read(tableManagementProvider.notifier);
    final name = _nameCtrl.text.trim();
    final order = int.parse(_orderCtrl.text.trim());

    if (_isEditing) {
      await notifier.updateFloor(
        floorId: widget.existing!.id,
        name: name,
        displayOrder: order,
      );
    } else {
      final floor = await notifier.createFloor(
        name: name,
        displayOrder: order,
      );
      // Auto-select the newly created floor.
      if (floor != null && mounted) {
        ref.read(selectedFloorProvider.notifier).state = floor.id;
      }
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteFloor() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteConfirmDialog(floorName: widget.existing!.name),
    );
    if (confirmed != true || !mounted) return;

    await ref
        .read(tableManagementProvider.notifier)
        .deleteFloor(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.accentDim,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.layers_rounded,
                          size: 18, color: AppColors.accent),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isEditing ? 'Edit Zone' : 'New Zone',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded,
                          size: 18, color: AppColors.textDim),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Zones group tables by physical area (indoor, terrace, bar…)',
                  style:
                      TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),

                // Zone name
                _label('Zone Name'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.textPrimary),
                  decoration: _inputDecoration('e.g. Main Hall, Terrace, Bar'),
                ),
                const SizedBox(height: 16),

                // Display order
                _label('Display Order'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _orderCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (int.tryParse(v.trim()) == null) return 'Invalid';
                    return null;
                  },
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.textPrimary),
                  decoration: _inputDecoration('0'),
                ),
                const SizedBox(height: 28),

                // Actions
                Row(
                  children: [
                    if (_isEditing)
                      GestureDetector(
                        onTap: _deleteFloor,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            color: AppColors.redDim,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.delete_outline_rounded,
                              size: 16, color: AppColors.red),
                        ),
                      ),
                    if (_isEditing) const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Text('Cancel',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: _saving ? null : _submit,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primaryContainer
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF0A1A3A)))
                              : Text(
                                  _isEditing ? 'Save' : 'Create Zone',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF0A1A3A)),
                                ),
                        ),
                      ),
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

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.5),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(fontSize: 13, color: AppColors.textDim),
        filled: true,
        fillColor: AppColors.bgInput,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        errorStyle: const TextStyle(fontSize: 11, color: AppColors.red),
      );
}

// ---------------------------------------------------------------------------
// Delete confirmation
// ---------------------------------------------------------------------------

class _DeleteConfirmDialog extends StatelessWidget {
  final String floorName;
  const _DeleteConfirmDialog({required this.floorName});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.redDim,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.red, size: 24),
            ),
            const SizedBox(height: 16),
            Text(
              'Delete "$floorName"?',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tables in this zone will not be deleted but will become unreachable until reassigned.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Text('Delete',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
