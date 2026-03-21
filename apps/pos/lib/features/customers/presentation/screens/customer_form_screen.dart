import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/customer_entity.dart';
import 'package:gastrocore_pos/features/customers/presentation/providers/customer_provider.dart';

/// Create a new customer or edit an existing one.
class CustomerFormScreen extends ConsumerStatefulWidget {
  final CustomerEntity? customer;

  const CustomerFormScreen({super.key, this.customer});

  bool get isEditing => customer != null;

  @override
  ConsumerState<CustomerFormScreen> createState() =>
      _CustomerFormScreenState();
}

class _CustomerFormScreenState
    extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _birthdayCtrl;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _phoneCtrl = TextEditingController(text: c?.phone ?? '');
    _emailCtrl = TextEditingController(text: c?.email ?? '');
    _addressCtrl = TextEditingController(text: c?.address ?? '');
    _notesCtrl = TextEditingController(text: c?.notes ?? '');
    _birthdayCtrl = TextEditingController(text: c?.birthday ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _birthdayCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _buildTopBar(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel(
                        label: 'Grundinformationen',
                        icon: Icons.person_rounded),
                    const SizedBox(height: 12),
                    _buildField(
                      controller: _nameCtrl,
                      label: 'Name *',
                      hint: 'Vor- und Nachname',
                      icon: Icons.badge_rounded,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Name ist erforderlich'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    _buildField(
                      controller: _phoneCtrl,
                      label: 'Telefon',
                      hint: '+41 79 000 00 00',
                      icon: Icons.phone_rounded,
                      keyboard: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    _buildField(
                      controller: _emailCtrl,
                      label: 'E-Mail',
                      hint: 'name@example.com',
                      icon: Icons.email_rounded,
                      keyboard: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(
                        label: 'Adresse & Geburtstag',
                        icon: Icons.location_on_rounded),
                    const SizedBox(height: 12),
                    _buildField(
                      controller: _addressCtrl,
                      label: 'Adresse',
                      hint: 'Strasse, PLZ Ort',
                      icon: Icons.home_rounded,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    _buildBirthdayField(),
                    const SizedBox(height: 24),
                    _SectionLabel(
                        label: 'Notizen', icon: Icons.sticky_note_2_rounded),
                    const SizedBox(height: 12),
                    _buildField(
                      controller: _notesCtrl,
                      label: 'Notizen',
                      hint:
                          'Allergien, Präferenzen, besondere Anforderungen…',
                      icon: Icons.notes_rounded,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 32),
                    _buildSaveButton(),
                    if (widget.isEditing) ...[
                      const SizedBox(height: 12),
                      _buildDeleteButton(context),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 64,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 18, color: AppColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            widget.isEditing ? 'Kunde bearbeiten' : 'Neuer Kunde',
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.5)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboard,
          maxLines: maxLines,
          validator: validator,
          style:
              const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(color: AppColors.textDim, fontSize: 14),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 14, right: 10),
              child: Icon(icon, size: 16, color: AppColors.textSecondary),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 40, minHeight: 40),
            filled: true,
            fillColor: AppColors.bgInput,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.borderFocused, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.red, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.red, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildBirthdayField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Geburtstag',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.5)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _pickBirthday,
          child: AbsorbPointer(
            child: TextFormField(
              controller: _birthdayCtrl,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'TT.MM.JJJJ',
                hintStyle:
                    const TextStyle(color: AppColors.textDim, fontSize: 14),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 14, right: 10),
                  child: Icon(Icons.cake_rounded,
                      size: 16, color: AppColors.textSecondary),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 40, minHeight: 40),
                suffixIcon: _birthdayCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded,
                            size: 16, color: AppColors.textSecondary),
                        onPressed: () =>
                            setState(() => _birthdayCtrl.clear()),
                      )
                    : null,
                filled: true,
                fillColor: AppColors.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: now,
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.surfaceContainer,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _birthdayCtrl.text =
            '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _saving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.surfaceDim,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppColors.surfaceDim),
              )
            : Text(
                widget.isEditing ? 'Änderungen speichern' : 'Kunde erstellen',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }

  Widget _buildDeleteButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: () => _confirmDelete(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.red,
          side: const BorderSide(color: AppColors.red, width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text(
          'Kunde löschen',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final notifier = ref.read(customerNotifierProvider.notifier);

    if (widget.isEditing) {
      final updated = widget.customer!.copyWith(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        address:
            _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        birthday: _birthdayCtrl.text.trim().isEmpty
            ? null
            : _birthdayCtrl.text.trim(),
        updatedAt: DateTime.now(),
      );
      await notifier.updateCustomer(updated);
    } else {
      final tenantId = ref.read(tenantIdProvider);
      await notifier.createCustomer(
        tenantId: tenantId,
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        address:
            _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        birthday: _birthdayCtrl.text.trim().isEmpty
            ? null
            : _birthdayCtrl.text.trim(),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: const Text('Kunde löschen',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
            'Möchten Sie diesen Kunden wirklich löschen?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen',
                style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref
          .read(customerNotifierProvider.notifier)
          .deleteCustomer(widget.customer!.id);
      if (mounted) {
        // Pop twice: form + detail screen
        Navigator.of(context)
          ..pop()
          ..maybePop();
      }
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
