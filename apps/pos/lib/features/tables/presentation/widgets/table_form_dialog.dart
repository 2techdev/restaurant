/// Dialog for creating or editing a restaurant table.
///
/// Covers: table name, capacity, shape (rectangle / square / circle),
/// and floor assignment. Position and dimensions are managed via the
/// drag-and-drop canvas and are not exposed here.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';

/// Shows the [TableFormDialog] as a modal bottom-sheet.
///
/// Pass [existing] to edit an existing table; omit it to create a new one.
/// [floorId] is required when creating.
Future<void> showTableFormDialog(
  BuildContext context, {
  RestaurantTableEntity? existing,
  String? floorId,
}) {
  return showDialog(
    context: context,
    builder: (_) => TableFormDialog(existing: existing, floorId: floorId),
  );
}

class TableFormDialog extends ConsumerStatefulWidget {
  final RestaurantTableEntity? existing;
  final String? floorId;

  const TableFormDialog({super.key, this.existing, this.floorId});

  @override
  ConsumerState<TableFormDialog> createState() => _TableFormDialogState();
}

class _TableFormDialogState extends ConsumerState<TableFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _capacityCtrl;
  late TableShape _shape;
  late TableZone _zone;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _capacityCtrl =
        TextEditingController(text: e?.capacity.toString() ?? '4');
    _shape = e?.shape ?? TableShape.rectangle;
    // Zone (pilot, provider-backed). Default İç Salon for new tables.
    final existingId = e?.id;
    final assignments = ref.read(tableZoneAssignmentsProvider);
    _zone = existingId != null
        ? tableZoneForId(assignments, existingId)
        : TableZone.icSalon;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final notifier = ref.read(tableManagementProvider.notifier);
    final capacity = int.parse(_capacityCtrl.text.trim());
    final name = _nameCtrl.text.trim();

    String? resultingId;
    if (_isEditing) {
      await notifier.updateTable(
        tableId: widget.existing!.id,
        name: name,
        capacity: capacity,
        shape: _shape,
      );
      resultingId = widget.existing!.id;
    } else {
      final floorId =
          widget.floorId ?? ref.read(selectedFloorProvider) ?? '';
      final created = await notifier.createTable(
        floorId: floorId,
        name: name,
        capacity: capacity,
        shape: _shape,
      );
      resultingId = created?.id;
    }

    // Persist zone assignment in the pilot provider map.
    if (resultingId != null) {
      final current =
          Map<String, TableZone>.from(ref.read(tableZoneAssignmentsProvider));
      current[resultingId] = _zone;
      ref.read(tableZoneAssignmentsProvider.notifier).state = current;
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 400,
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
                      child: const Icon(Icons.table_restaurant_rounded,
                          size: 18, color: AppColors.accent),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isEditing ? 'Edit Table' : 'New Table',
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
                const SizedBox(height: 24),

                // Table name
                _FieldLabel('Table Name'),
                const SizedBox(height: 6),
                _buildTextField(
                  controller: _nameCtrl,
                  hint: 'e.g. T1, Bar 3, Terrace 12',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                // Capacity
                _FieldLabel('Capacity (seats)'),
                const SizedBox(height: 6),
                _buildTextField(
                  controller: _capacityCtrl,
                  hint: '4',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 1) return 'Must be ≥ 1';
                    if (n > 50) return 'Must be ≤ 50';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Shape
                _FieldLabel('Shape'),
                const SizedBox(height: 8),
                Row(
                  children: TableShape.values.map((shape) {
                    final isSelected = _shape == shape;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _shape = shape),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.accentDim
                                : AppColors.surfaceContainerHigh,
                            borderRadius: shape == TableShape.circle
                                ? BorderRadius.circular(40)
                                : BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(
                                    color: AppColors.accent, width: 1.5)
                                : null,
                          ),
                          child: Column(
                            children: [
                              _ShapeIcon(shape),
                              const SizedBox(height: 4),
                              Text(
                                _shapeName(shape),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected
                                      ? AppColors.accent
                                      : AppColors.textSecondary,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Zone (pilot, not persisted to DB yet)
                _FieldLabel('Bölge'),
                const SizedBox(height: 8),
                Row(
                  children: <TableZone>[
                    TableZone.icSalon,
                    TableZone.teras,
                    TableZone.bar,
                  ].map((zone) {
                    final isSelected = _zone == zone;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _zone = zone),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.accentDim
                                : AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(
                                    color: AppColors.accent, width: 1.5)
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            tableZoneLabel(zone),
                            style: TextStyle(
                              fontSize: 11,
                              color: isSelected
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: _OutlineButton(
                        label: 'Cancel',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PrimaryButton(
                        label: _isEditing ? 'Save Changes' : 'Create Table',
                        isLoading: _saving,
                        onTap: _submit,
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
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
      ),
    );
  }

  String _shapeName(TableShape s) => switch (s) {
        TableShape.rectangle => 'Rectangle',
        TableShape.square => 'Square',
        TableShape.circle => 'Circle',
      };
}

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5),
    );
  }
}

class _ShapeIcon extends StatelessWidget {
  final TableShape shape;
  const _ShapeIcon(this.shape);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 18),
      painter: _ShapePainter(shape),
    );
  }
}

class _ShapePainter extends CustomPainter {
  final TableShape shape;
  _ShapePainter(this.shape);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textSecondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    switch (shape) {
      case TableShape.rectangle:
        canvas.drawRRect(
            RRect.fromLTRBR(2, 2, size.width - 2, size.height - 2,
                const Radius.circular(2)),
            paint);
      case TableShape.square:
        final s = size.height - 4;
        final x = (size.width - s) / 2;
        canvas.drawRRect(
            RRect.fromLTRBR(x, 2, x + s, 2 + s, const Radius.circular(2)),
            paint);
      case TableShape.circle:
        canvas.drawOval(
            Rect.fromLTWH(2, 2, size.width - 4, size.height - 4), paint);
    }
  }

  @override
  bool shouldRepaint(_ShapePainter old) => old.shape != shape;
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onTap;

  const _PrimaryButton(
      {required this.label, required this.onTap, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryContainer]),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF0A1A3A)))
            : Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0A1A3A))),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _OutlineButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary)),
      ),
    );
  }
}
