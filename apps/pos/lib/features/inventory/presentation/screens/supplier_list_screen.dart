/// Supplier management screen.
///
/// Lists all suppliers with contact info. Add/edit via bottom sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/inventory/domain/entities/supplier_entity.dart';
import 'package:gastrocore_pos/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

class SupplierListScreen extends ConsumerWidget {
  const SupplierListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final suppliersAsync = ref.watch(suppliersStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainer,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ),
        title: Text(
          l10n.invSuppliers,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSupplierSheet(context, ref),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surfaceDim,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.invAddSupplier),
      ),
      body: suppliersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(e.toString(), style: const TextStyle(color: AppColors.red)),
        ),
        data: (suppliers) {
          if (suppliers.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    size: 56,
                    color: AppColors.textDim,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.statusNoData,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: suppliers.length,
            itemBuilder: (_, i) => _SupplierCard(
              supplier: suppliers[i],
              onEdit: () => _showSupplierSheet(context, ref, supplier: suppliers[i]),
              onDelete: () => _confirmDelete(context, ref, suppliers[i], l10n),
            ),
          );
        },
      ),
    );
  }

  void _showSupplierSheet(
    BuildContext context,
    WidgetRef ref, {
    SupplierEntity? supplier,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SupplierSheet(
        tenantId: ref.read(tenantIdProvider),
        existing: supplier,
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SupplierEntity supplier,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: Text(l10n.confirmDelete,
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(
          supplier.name,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionCancel,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref
                  .read(inventoryActionsProvider.notifier)
                  .deleteSupplier(supplier.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Supplier card
// ---------------------------------------------------------------------------

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.supplier,
    required this.onEdit,
    required this.onDelete,
  });

  final SupplierEntity supplier;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    supplier.name.isNotEmpty
                        ? supplier.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (supplier.email != null) ...[
                      const SizedBox(height: 3),
                      _ContactRow(
                        icon: Icons.email_outlined,
                        text: supplier.email!,
                      ),
                    ],
                    if (supplier.phone != null) ...[
                      const SizedBox(height: 3),
                      _ContactRow(
                        icon: Icons.phone_outlined,
                        text: supplier.phone!,
                      ),
                    ],
                    if (supplier.address != null) ...[
                      const SizedBox(height: 3),
                      _ContactRow(
                        icon: Icons.location_on_outlined,
                        text: supplier.address!,
                      ),
                    ],
                  ],
                ),
              ),

              // Actions
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                color: AppColors.surfaceContainerHigh,
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppColors.textDim, size: 18),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined,
                            size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Text(
                          'Edit',
                          style: const TextStyle(color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: const [
                        Icon(Icons.delete_outline_rounded,
                            size: 16, color: AppColors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: AppColors.red)),
                      ],
                    ),
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

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppColors.textDim),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.textDim),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Add/Edit supplier bottom sheet
// ---------------------------------------------------------------------------

class _SupplierSheet extends ConsumerStatefulWidget {
  const _SupplierSheet({required this.tenantId, this.existing});

  final String tenantId;
  final SupplierEntity? existing;

  @override
  ConsumerState<_SupplierSheet> createState() => _SupplierSheetState();
}

class _SupplierSheetState extends ConsumerState<_SupplierSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _emailCtrl = TextEditingController(text: s?.email ?? '');
    _phoneCtrl = TextEditingController(text: s?.phone ?? '');
    _addressCtrl = TextEditingController(text: s?.address ?? '');
    _notesCtrl = TextEditingController(text: s?.notes ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEdit ? l10n.actionEdit : l10n.invAddSupplier,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              _field(l10n.invSupplierName, _nameCtrl, required: true),
              const SizedBox(height: 12),
              _field(l10n.invSupplierEmail, _emailCtrl),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _field(l10n.invSupplierPhone, _phoneCtrl)),
                ],
              ),
              const SizedBox(height: 12),
              _field(l10n.invSupplierAddress, _addressCtrl),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.surfaceDim,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          l10n.actionSave,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        TextFormField(
          controller: ctrl,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.bgInput,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          validator:
              required ? (v) => (v == null || v.trim().isEmpty) ? '!' : null : null,
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final actions = ref.read(inventoryActionsProvider.notifier);
    final existing = widget.existing;
    bool ok;

    if (existing != null) {
      ok = await actions.updateSupplier(
        existing.copyWith(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          address:
              _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
          notes:
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        ),
      );
    } else {
      final supplier = actions.buildNewSupplier(
        tenantId: widget.tenantId,
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        address:
            _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        notes:
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      ok = await actions.createSupplier(supplier);
    }

    if (mounted) {
      setState(() => _saving = false);
      if (ok) Navigator.of(context).pop();
    }
  }
}
