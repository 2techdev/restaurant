/// Station management screen — lets the restaurant admin add, rename,
/// reorder, and deactivate kitchen stations.
///
/// Reached from the KDS settings screen. Default stations cannot be
/// deleted, only toggled inactive, so the 'kitchen' fallback for mixed
/// tickets is guaranteed to exist.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/kds_app/router/kds_router.dart';
import 'package:gastrocore_pos/features/stations/domain/entities/station_entity.dart';
import 'package:gastrocore_pos/features/stations/presentation/providers/station_provider.dart';

class StationSettingsScreen extends ConsumerWidget {
  const StationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stationsAsync = ref.watch(allStationsProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D27),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textSecondary),
          onPressed: () => context.go(KdsRoutes.settings),
        ),
        title: const Text(
          'Kitchen Stations',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: const Color(0xFF001944),
        icon: const Icon(Icons.add),
        label: const Text(
          'New Station',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        onPressed: () => _openEditor(context, ref, null),
      ),
      body: stationsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(
            'Failed to load stations: $err',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        data: (stations) {
          if (stations.isEmpty) {
            return const Center(
              child: Text(
                'No stations yet — tap "New Station".',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
            itemCount: stations.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final s = stations[i];
              return _StationRow(
                station: s,
                onTap: () => _openEditor(context, ref, s),
                onToggle: (value) => ref
                    .read(stationRepositoryProvider)
                    .setActive(s.id, value),
                onDelete: s.isDefault
                    ? null
                    : () => _confirmDelete(context, ref, s),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    StationEntity? existing,
  ) async {
    final result = await showDialog<_StationEditorResult>(
      context: context,
      builder: (_) => _StationEditorDialog(existing: existing),
    );
    if (result == null) return;

    final repo = ref.read(stationRepositoryProvider);
    final tenantId = ref.read(tenantIdProvider);

    if (existing == null) {
      await repo.upsert(
        StationEntity(
          id: IdGenerator.generateId(),
          tenantId: tenantId,
          code: result.code,
          name: result.name,
          icon: result.iconCodepoint?.toString(),
          color: result.color,
          sortOrder: result.sortOrder,
          isDefault: false,
          isActive: true,
        ),
      );
    } else {
      await repo.upsert(existing.copyWith(
        code: result.code,
        name: result.name,
        icon: result.iconCodepoint?.toString(),
        color: result.color,
        sortOrder: result.sortOrder,
      ));
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    StationEntity station,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: Text('Delete ${station.name}?',
            style: const TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This station will no longer appear in the KDS filter. '
          'Tickets already routed to it remain.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(stationRepositoryProvider).softDelete(station.id);
  }
}

// ---------------------------------------------------------------------------
// Station row
// ---------------------------------------------------------------------------

class _StationRow extends StatelessWidget {
  final StationEntity station;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onDelete;

  const _StationRow({
    required this.station,
    required this.onTap,
    required this.onToggle,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = station.accentColor ?? AppColors.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: station.isActive
                  ? accent.withValues(alpha: 0.35)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(station.iconData, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          station.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (station.isDefault) ...[
                          const SizedBox(width: 8),
                          const _Chip(text: 'default'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'code: ${station.code}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: station.isActive,
                onChanged: onToggle,
                activeThumbColor: AppColors.primary,
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.textSecondary),
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Editor dialog
// ---------------------------------------------------------------------------

class _StationEditorResult {
  final String code;
  final String name;
  final int? iconCodepoint;
  final String? color;
  final int sortOrder;

  const _StationEditorResult({
    required this.code,
    required this.name,
    required this.sortOrder,
    this.iconCodepoint,
    this.color,
  });
}

class _StationEditorDialog extends StatefulWidget {
  final StationEntity? existing;
  const _StationEditorDialog({this.existing});

  @override
  State<_StationEditorDialog> createState() => _StationEditorDialogState();
}

class _StationEditorDialogState extends State<_StationEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _sortCtrl;
  late IconData _icon;
  late String _color;

  static const _iconChoices = <IconData>[
    Icons.local_fire_department,
    Icons.outdoor_grill,
    Icons.ac_unit,
    Icons.cake,
    Icons.local_bar,
    Icons.set_meal,
    Icons.restaurant,
    Icons.rice_bowl,
    Icons.soup_kitchen,
    Icons.coffee,
  ];

  static const _colorChoices = <String>[
    '#FB923C',
    '#EF4444',
    '#38BDF8',
    '#BF5AF2',
    '#FACC15',
    '#22C55E',
    '#F97316',
    '#06B6D4',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _codeCtrl = TextEditingController(text: e?.code ?? '');
    _sortCtrl = TextEditingController(text: (e?.sortOrder ?? 99).toString());
    _icon = e?.iconData ?? Icons.restaurant;
    _color = e?.color ?? _colorChoices.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final code = _codeCtrl.text.trim().toLowerCase();
    if (name.isEmpty || code.isEmpty) return;

    Navigator.pop(
      context,
      _StationEditorResult(
        name: name,
        code: code,
        iconCodepoint: _icon.codePoint,
        color: _color,
        sortOrder: int.tryParse(_sortCtrl.text.trim()) ?? 99,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Dialog(
      backgroundColor: AppColors.surfaceContainerHigh,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEdit ? 'Edit Station' : 'New Station',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _field(
                label: 'Display Name',
                hint: 'Grill',
                controller: _nameCtrl,
              ),
              const SizedBox(height: 12),
              _field(
                label: 'Code (printer group)',
                hint: 'grill',
                controller: _codeCtrl,
                enabled: !(widget.existing?.isDefault ?? false),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                ],
              ),
              const SizedBox(height: 12),
              _field(
                label: 'Sort Order',
                hint: '1',
                controller: _sortCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 14),
              const Text('Icon',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _iconChoices.map((ic) {
                  final selected = ic.codePoint == _icon.codePoint;
                  return GestureDetector(
                    onTap: () => setState(() => _icon = ic),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.2)
                            : AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(ic,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              const Text('Color',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _colorChoices.map((hex) {
                  final selected = hex == _color;
                  return GestureDetector(
                    onTap: () => setState(() => _color = hex),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _parse(hex),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected
                              ? Colors.white
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: const Color(0xFF001944),
                    ),
                    onPressed: _submit,
                    child: Text(isEdit ? 'Save' : 'Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter> inputFormatters = const [],
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          enabled: enabled,
          inputFormatters: inputFormatters,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(color: AppColors.textDim, fontSize: 14),
            filled: true,
            fillColor: AppColors.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Color _parse(String hex) {
    final clean = hex.replaceFirst('#', '');
    final value = int.tryParse(clean, radix: 16) ?? 0xFFFFFF;
    return Color(0xFF000000 | value);
  }
}
