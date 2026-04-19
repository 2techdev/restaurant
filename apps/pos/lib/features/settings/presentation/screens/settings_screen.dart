/// Settings screen for GastroCore POS.
///
/// Sidebar navigation with nine sections:
///   1. Restaurant — name, address, phone, MWST-Nr, logo
///   2. Printer    — connection type, IP, port, test print
///   3. Payment    — Wallee / MyPOS terminal config
///   4. Receipt    — header/footer text, logo, QR code
///   5. Tax        — Swiss MWST rates (8.1 / 3.8 / 2.6 %)
///   6. Appearance — dark/light theme, language
///   7. Backup     — SQLite DB export / import
///   8. About      — version, license
///
/// All settings are persisted via SharedPreferences through Riverpod
/// [StateNotifier] providers (see settings_provider.dart).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_pos/core/printing/printer_device.dart';
import 'package:gastrocore_pos/core/printing/printing_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:gastrocore_pos/core/data/seed_data.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/app_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/payment_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/printer_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/receipt_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/tax_settings.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/favorites_bar.dart';
import 'package:gastrocore_pos/core/services/backup_service.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/permission.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/backup_provider.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/app_feature.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/license_tier.dart';
import 'package:gastrocore_pos/features/licensing/domain/repositories/license_repository.dart';
import 'package:gastrocore_pos/features/licensing/presentation/providers/license_provider.dart';
import 'package:gastrocore_pos/features/licensing/presentation/widgets/feature_gate.dart';
import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// Section enum
// ---------------------------------------------------------------------------

enum _Section {
  restaurant('Restaurant', Icons.storefront_rounded),
  printer('Printer', Icons.print_rounded),
  payment('Payment', Icons.payment_rounded),
  receipt('Receipt', Icons.receipt_long_rounded),
  tax('Tax (MWST)', Icons.calculate_rounded),
  favorites('Hızlı Erişim Butonları', Icons.star_rounded),
  reports('Reports', Icons.assessment_rounded),
  appearance('Appearance', Icons.palette_rounded),
  backup('Backup & Restore', Icons.backup_rounded),
  auditLog('Audit Log', Icons.history_rounded),
  demoData('Demo Data', Icons.science_outlined),
  upgrade('License & Upgrade', Icons.workspace_premium_rounded),
  about('About', Icons.info_outline_rounded);

  const _Section(this.label, this.icon);

  final String label;
  final IconData icon;
}

// ---------------------------------------------------------------------------
// SettingsScreen
// ---------------------------------------------------------------------------

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _Section _selected = _Section.restaurant;

  @override
  Widget build(BuildContext context) {
    // Role gate: Settings requires Yönetici (admin).
    final canOpen = ref.watch(canProvider(Permission.settings));
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _TopBar(onBack: _navigateBack),
          Expanded(
            child: canOpen
                ? Row(
                    children: [
                      _Sidebar(
                        selected: _selected,
                        onSelect: (s) => setState(() => _selected = s),
                      ),
                      Expanded(child: _buildContent()),
                    ],
                  )
                : const _AccessDeniedPane(),
          ),
        ],
      ),
    );
  }

  void _navigateBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Widget _buildContent() {
    return switch (_selected) {
      _Section.restaurant => const _RestaurantSection(),
      _Section.printer => const _PrinterSection(),
      _Section.payment => const _PaymentSection(),
      _Section.receipt => const _ReceiptSection(),
      _Section.tax => const _TaxSection(),
      _Section.favorites => const _FavoritesSection(),
      _Section.reports => _ReportsSection(onNavigate: _navigateBack),
      _Section.appearance => const _AppearanceSection(),
      _Section.backup => const _BackupSection(),
      _Section.auditLog => _AuditLogLinkSection(onNavigate: _navigateBack),
      _Section.demoData => const _DemoDataSection(),
      _Section.upgrade => const _UpgradeSection(),
      _Section.about => const _AboutSection(),
    };
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: AppColors.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _IconBtn(icon: Icons.arrow_back_rounded, onTap: onBack),
          const SizedBox(width: 12),
          _GastroCoreLogo(),
          const SizedBox(width: 16),
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          _TextBtn(label: 'Back', onTap: onBack),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sidebar
// ---------------------------------------------------------------------------

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect});

  final _Section selected;
  final ValueChanged<_Section> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: _Section.values
            .map(
              (s) => _SidebarItem(
                section: s,
                isSelected: s == selected,
                onTap: () => onSelect(s),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.section,
    required this.isSelected,
    required this.onTap,
  });

  final _Section section;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isSelected
            ? AppColors.accentDim
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  section.icon,
                  size: 18,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  section.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section scaffold helpers
// ---------------------------------------------------------------------------

class _SectionScaffold extends StatelessWidget {
  const _SectionScaffold({
    required this.title,
    required this.children,
    this.action,
  });

  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              if (action != null) ...[
                const Spacer(),
                action!,
              ],
            ],
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.title});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
          ],
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            maxLines: maxLines,
            onChanged: onChanged,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: AppColors.textDim,
                fontSize: 14,
              ),
              filled: true,
              fillColor: AppColors.bgInput,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: AppColors.borderFocused,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _SaveBtn extends StatelessWidget {
  const _SaveBtn({required this.onPressed, this.label = 'Save'});

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surfaceDim,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. RESTAURANT SECTION
// ---------------------------------------------------------------------------

class _RestaurantSection extends ConsumerStatefulWidget {
  const _RestaurantSection();

  @override
  ConsumerState<_RestaurantSection> createState() =>
      _RestaurantSectionState();
}

class _RestaurantSectionState extends ConsumerState<_RestaurantSection> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _mwstCtrl = TextEditingController();
  String? _mwstError;
  bool _initialised = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _mwstCtrl.dispose();
    super.dispose();
  }

  void _populate(RestaurantSettings s) {
    if (_initialised) return;
    _nameCtrl.text = s.name;
    _addressCtrl.text = s.address;
    _phoneCtrl.text = s.phone;
    _mwstCtrl.text = s.mwstNr;
    _initialised = true;
  }

  Future<void> _save() async {
    // Validate MWST-Nr before saving.
    final mwstValidation = validateMwstNr(_mwstCtrl.text.trim());
    if (mwstValidation != null) {
      setState(() => _mwstError = mwstValidation);
      return;
    }
    setState(() => _mwstError = null);

    final notifier =
        ref.read(restaurantSettingsProvider.notifier);
    await notifier.save(RestaurantSettings(
      name: _nameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      mwstNr: _mwstCtrl.text.trim(),
      logoPath:
          ref.read(restaurantSettingsProvider).valueOrNull?.logoPath,
    ));
    if (mounted) {
      _showSnack('Restaurant settings saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(restaurantSettingsProvider);
    settingsAsync.whenData(_populate);

    return _SectionScaffold(
      title: 'Restaurant',
      action: _SaveBtn(onPressed: _save),
      children: [
        _Card(
          title: 'IDENTITY',
          children: [
            _Field(
              label: 'Restaurant Name',
              controller: _nameCtrl,
              hint: 'e.g. Restaurant Zum Löwen',
            ),
            _Field(
              label: 'Address',
              controller: _addressCtrl,
              hint: 'e.g. Hauptstrasse 12, 8001 Zürich',
              maxLines: 2,
            ),
            _Field(
              label: 'Phone',
              controller: _phoneCtrl,
              hint: '+41 44 123 45 67',
              keyboardType: TextInputType.phone,
            ),
            // MWST-Nr with inline validation
            _Field(
              label: 'MWST-Nr (Swiss VAT Number)',
              controller: _mwstCtrl,
              hint: 'CHE-123.456.789 MWST',
              onChanged: (v) {
                final err = validateMwstNr(v.trim());
                if (err != _mwstError) setState(() => _mwstError = err);
              },
            ),
            if (_mwstError != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 14, color: AppColors.red),
                  const SizedBox(width: 6),
                  Text(
                    _mwstError!,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.red),
                  ),
                ],
              ),
            ] else if (_mwstCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              const Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded,
                      size: 14, color: AppColors.green),
                  SizedBox(width: 6),
                  Text(
                    'Valid Swiss MWST-Nr',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.green),
                  ),
                ],
              ),
            ],
          ],
        ),
        _Card(
          title: 'LOGO',
          children: [
            settingsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(
                'Error: $e',
                style: const TextStyle(color: AppColors.red),
              ),
              data: (s) => _LogoRow(settings: s),
            ),
          ],
        ),
        _Card(
          title: 'WORKFLOW',
          children: [
            _Toggle(
              label: 'Require shift start after login',
              subtitle:
                  'When on, cashiers must record opening cash after PIN '
                  'login. Turn off for card-only / fast-casual concepts '
                  'where login drops straight into the order center.',
              value: settingsAsync.valueOrNull?.shiftStartRequired ?? true,
              onChanged: (v) => ref
                  .read(restaurantSettingsProvider.notifier)
                  .update((s) => s.copyWith(shiftStartRequired: v)),
            ),
          ],
        ),
      ],
    );
  }
}

class _LogoRow extends ConsumerWidget {
  const _LogoRow({required this.settings});

  final RestaurantSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        // Logo preview
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: settings.logoPath != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(settings.logoPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_rounded,
                      color: AppColors.textDim,
                    ),
                  ),
                )
              : const Icon(
                  Icons.add_photo_alternate_rounded,
                  color: AppColors.textDim,
                  size: 32,
                ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Logo file path (absolute)',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              settings.logoPath ?? 'No logo set',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (settings.logoPath != null)
              _TextBtn(
                label: 'Remove logo',
                onTap: () => ref
                    .read(restaurantSettingsProvider.notifier)
                    .save(settings.copyWith(clearLogo: true)),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 2. PRINTER SECTION
// ---------------------------------------------------------------------------

class _PrinterSection extends ConsumerStatefulWidget {
  const _PrinterSection();

  @override
  ConsumerState<_PrinterSection> createState() => _PrinterSectionState();
}

class _PrinterSectionState extends ConsumerState<_PrinterSection> {
  final _receiptIpCtrl = TextEditingController();
  final _receiptPortCtrl = TextEditingController();
  final _kitchenIpCtrl = TextEditingController();
  final _kitchenPortCtrl = TextEditingController();
  bool _initialised = false;
  String? _testResult;

  // Bluetooth discovery state
  List<PrinterDevice> _btDevices = [];
  bool _btScanning = false;
  String? _btError;

  @override
  void dispose() {
    _receiptIpCtrl.dispose();
    _receiptPortCtrl.dispose();
    _kitchenIpCtrl.dispose();
    _kitchenPortCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanBluetooth() async {
    setState(() {
      _btScanning = true;
      _btError = null;
    });
    try {
      final devices =
          await ref.read(printerServiceProvider).discoverBluetoothPrinters();
      setState(() {
        _btDevices = devices;
        _btScanning = false;
        if (devices.isEmpty) {
          _btError =
              'No paired Bluetooth printers found. Pair the printer in Android Bluetooth settings first.';
        }
      });
    } catch (e) {
      setState(() {
        _btScanning = false;
        _btError = 'Scan failed: $e';
      });
    }
  }

  Future<void> _selectBtDevice(PrinterDevice device) async {
    await ref.read(printerSettingsProvider.notifier).update(
          (s) => s.copyWith(
            bluetoothDeviceAddress: device.address,
            bluetoothDeviceName: device.name,
          ),
        );
    if (mounted) _showSnack('Bluetooth printer selected: ${device.name}');
  }

  void _populate(PrinterSettings s) {
    if (_initialised) return;
    _receiptIpCtrl.text = s.receiptPrinterIp;
    _receiptPortCtrl.text = s.receiptPrinterPort.toString();
    _kitchenIpCtrl.text = s.kitchenPrinterIp;
    _kitchenPortCtrl.text = s.kitchenPrinterPort.toString();
    _initialised = true;
  }

  Future<void> _save() async {
    final current =
        ref.read(printerSettingsProvider).valueOrNull ?? const PrinterSettings();
    await ref.read(printerSettingsProvider.notifier).save(current.copyWith(
          receiptPrinterIp: _receiptIpCtrl.text.trim(),
          receiptPrinterPort:
              int.tryParse(_receiptPortCtrl.text.trim()) ?? 9100,
          kitchenPrinterIp: _kitchenIpCtrl.text.trim(),
          kitchenPrinterPort:
              int.tryParse(_kitchenPortCtrl.text.trim()) ?? 9100,
        ));
    if (mounted) _showSnack('Printer settings saved.');
  }

  Future<void> _testPrint() async {
    final s =
        ref.read(printerSettingsProvider).valueOrNull ?? const PrinterSettings();
    setState(() => _testResult = 'Connecting to ${s.receiptPrinterIp}…');

    try {
      final socket = await Socket.connect(
        s.receiptPrinterIp,
        s.receiptPrinterPort,
        timeout: const Duration(seconds: 5),
      );
      // Send minimal ESC/POS test page
      socket.add([
        0x1B, 0x40, // ESC @ — initialize
        0x1B, 0x61, 0x01, // center align
        ...('GastroCore POS\n').codeUnits,
        ...('--- Test Print ---\n').codeUnits,
        0x1B, 0x64, 0x03, // feed 3 lines
        0x1D, 0x56, 0x42, 0x00, // cut
      ]);
      await socket.flush();
      await socket.close();
      if (mounted) setState(() => _testResult = 'Test page sent successfully.');
    } catch (e) {
      if (mounted) setState(() => _testResult = 'Connection failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(printerSettingsProvider);
    settingsAsync.whenData(_populate);
    final settings = settingsAsync.valueOrNull ?? const PrinterSettings();

    return _SectionScaffold(
      title: 'Printer',
      action: _SaveBtn(onPressed: _save),
      children: [
        _Card(
          title: 'CONNECTION',
          children: [
            const Text(
              'Connection Type',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            _SegmentedRow<PrinterConnectionType>(
              values: PrinterConnectionType.values,
              current: settings.connectionType,
              labelOf: (v) => v.label,
              onChanged: (v) => ref
                  .read(printerSettingsProvider.notifier)
                  .update((s) => s.copyWith(connectionType: v)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Paper Width',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            _SegmentedRow<PaperWidth>(
              values: PaperWidth.values,
              current: settings.paperWidth,
              labelOf: (v) => v.label,
              onChanged: (v) => ref
                  .read(printerSettingsProvider.notifier)
                  .update((s) => s.copyWith(paperWidth: v)),
            ),
          ],
        ),
        if (settings.connectionType == PrinterConnectionType.bluetooth)
          _Card(
            title: 'BLUETOOTH PRINTER',
            children: [
              // Currently selected device
              if (settings.bluetoothDeviceAddress.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accentDim,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bluetooth_connected_rounded,
                          size: 18, color: AppColors.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              settings.bluetoothDeviceName.isNotEmpty
                                  ? settings.bluetoothDeviceName
                                  : 'Unknown device',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accent),
                            ),
                            Text(
                              settings.bluetoothDeviceAddress,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => ref
                            .read(printerSettingsProvider.notifier)
                            .update((s) => s.copyWith(
                                  bluetoothDeviceAddress: '',
                                  bluetoothDeviceName: '',
                                )),
                        child: const Icon(Icons.close_rounded,
                            size: 16, color: AppColors.textDim),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Discover button
              _OutlineBtn(
                label: _btScanning
                    ? 'Scanning…'
                    : 'Discover Paired Devices',
                icon: Icons.bluetooth_searching_rounded,
                onPressed: _btScanning ? null : _scanBluetooth,
              ),

              // Error message
              if (_btError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _btError!,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.orange),
                  ),
                ),

              // Discovered device list
              if (_btDevices.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'PAIRED DEVICES',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDim,
                      letterSpacing: 1),
                ),
                const SizedBox(height: 6),
                ..._btDevices.map(
                  (device) => GestureDetector(
                    onTap: () => _selectBtDevice(device),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: device.address ==
                                settings.bluetoothDeviceAddress
                            ? AppColors.accentDim
                            : AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: device.address ==
                                  settings.bluetoothDeviceAddress
                              ? AppColors.accent.withValues(alpha: 0.4)
                              : AppColors.border.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.bluetooth_rounded,
                            size: 16,
                            color: device.address ==
                                    settings.bluetoothDeviceAddress
                                ? AppColors.accent
                                : AppColors.textDim,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  device.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: device.address ==
                                            settings.bluetoothDeviceAddress
                                        ? AppColors.accent
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  device.address,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textDim),
                                ),
                              ],
                            ),
                          ),
                          if (device.address ==
                              settings.bluetoothDeviceAddress)
                            const Icon(Icons.check_circle_rounded,
                                size: 16, color: AppColors.accent),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 8),
              const Text(
                'Note: Only devices already paired in Android system Bluetooth settings are shown. '
                'ESC/POS via RFCOMM SPP (UUID 00001101…).',
                style: TextStyle(fontSize: 11, color: AppColors.textDim),
              ),
            ],
          )
        else ...[
          _Card(
            title: 'RECEIPT PRINTER',
            children: [
              _Field(
                label: 'IP Address',
                controller: _receiptIpCtrl,
                hint: '192.168.1.100',
                keyboardType: TextInputType.text,
              ),
              _Field(
                label: 'TCP Port',
                controller: _receiptPortCtrl,
                hint: '9100',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              Row(
                children: [
                  _OutlineBtn(
                    label: 'Test Print',
                    icon: Icons.print_rounded,
                    onPressed: _testPrint,
                  ),
                  const SizedBox(width: 12),
                  if (_testResult != null)
                    Expanded(
                      child: Text(
                        _testResult!,
                        style: TextStyle(
                          fontSize: 13,
                          color: _testResult!.contains('success')
                              ? AppColors.green
                              : AppColors.orange,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          _Card(
            title: 'KITCHEN PRINTER',
            children: [
              _Field(
                label: 'IP Address',
                controller: _kitchenIpCtrl,
                hint: '192.168.1.101',
              ),
              _Field(
                label: 'TCP Port',
                controller: _kitchenPortCtrl,
                hint: '9100',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],
          ),
        ],
        _Card(
          title: 'BEHAVIOUR',
          children: [
            _Toggle(
              label: 'Auto-print receipt on payment',
              value: settings.autoPrintOnPayment,
              onChanged: (v) => ref
                  .read(printerSettingsProvider.notifier)
                  .update((s) => s.copyWith(autoPrintOnPayment: v)),
            ),
            _Toggle(
              label: 'Auto-send kitchen ticket',
              value: settings.autoPrintKitchenTicket,
              onChanged: (v) => ref
                  .read(printerSettingsProvider.notifier)
                  .update((s) => s.copyWith(autoPrintKitchenTicket: v)),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. PAYMENT SECTION
// ---------------------------------------------------------------------------

class _PaymentSection extends ConsumerStatefulWidget {
  const _PaymentSection();

  @override
  ConsumerState<_PaymentSection> createState() => _PaymentSectionState();
}

class _PaymentSectionState extends ConsumerState<_PaymentSection> {
  final _walleeIpCtrl = TextEditingController();
  final _walleePortCtrl = TextEditingController();
  final _walleePosIdCtrl = TextEditingController();
  final _myposIpCtrl = TextEditingController();
  final _myposPortCtrl = TextEditingController();
  final _myposCurrencyCtrl = TextEditingController();
  bool _initialised = false;

  @override
  void dispose() {
    _walleeIpCtrl.dispose();
    _walleePortCtrl.dispose();
    _walleePosIdCtrl.dispose();
    _myposIpCtrl.dispose();
    _myposPortCtrl.dispose();
    _myposCurrencyCtrl.dispose();
    super.dispose();
  }

  void _populate(PaymentSettings s) {
    if (_initialised) return;
    _walleeIpCtrl.text = s.wallee.terminalIp;
    _walleePortCtrl.text = s.wallee.terminalPort.toString();
    _walleePosIdCtrl.text = s.wallee.posId;
    _myposIpCtrl.text = s.mypos.ip;
    _myposPortCtrl.text = s.mypos.port.toString();
    _myposCurrencyCtrl.text = s.mypos.currency;
    _initialised = true;
  }

  Future<void> _save() async {
    final current = ref.read(paymentSettingsProvider).valueOrNull ??
        const PaymentSettings();
    await ref.read(paymentSettingsProvider.notifier).save(current.copyWith(
          wallee: WalleeConfig(
            terminalIp: _walleeIpCtrl.text.trim(),
            terminalPort:
                int.tryParse(_walleePortCtrl.text.trim()) ?? 50000,
            posId: _walleePosIdCtrl.text.trim(),
          ),
          mypos: MyPosConfig(
            ip: _myposIpCtrl.text.trim(),
            port: int.tryParse(_myposPortCtrl.text.trim()) ?? 50100,
            currency: _myposCurrencyCtrl.text.trim().toUpperCase(),
          ),
        ));
    if (mounted) _showSnack('Payment settings saved.');
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(paymentSettingsProvider);
    settingsAsync.whenData(_populate);
    final settings =
        settingsAsync.valueOrNull ?? const PaymentSettings();

    return _SectionScaffold(
      title: 'Payment',
      action: _SaveBtn(onPressed: _save),
      children: [
        _Card(
          title: 'ACTIVE GATEWAY',
          children: [
            const Text(
              'Select the payment terminal connected to this POS.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            RadioGroup<PaymentGateway>(
              groupValue: settings.activeGateway,
              onChanged: (v) => ref
                  .read(paymentSettingsProvider.notifier)
                  .update((s) => s.copyWith(activeGateway: v)),
              child: Column(
                children: PaymentGateway.values
                    .map(
                      (gw) => RadioListTile<PaymentGateway>(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          gw.label,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        value: gw,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
        _Card(
          title: 'WALLEE TERMINAL (LTI)',
          children: [
            _Field(
              label: 'Terminal IP',
              controller: _walleeIpCtrl,
              hint: '192.168.1.200',
            ),
            _Field(
              label: 'LTI Port',
              controller: _walleePortCtrl,
              hint: '50000',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            _Field(
              label: 'POS ID',
              controller: _walleePosIdCtrl,
              hint: 'e.g. POS-01',
            ),
          ],
        ),
        _Card(
          title: 'MYPOS TERMINAL',
          children: [
            _Field(
              label: 'Terminal IP',
              controller: _myposIpCtrl,
              hint: '192.168.1.201',
            ),
            _Field(
              label: 'Port',
              controller: _myposPortCtrl,
              hint: '50100',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            _Field(
              label: 'Currency',
              controller: _myposCurrencyCtrl,
              hint: 'CHF',
              keyboardType: TextInputType.text,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 4. RECEIPT SECTION
// ---------------------------------------------------------------------------

class _ReceiptSection extends ConsumerStatefulWidget {
  const _ReceiptSection();

  @override
  ConsumerState<_ReceiptSection> createState() => _ReceiptSectionState();
}

class _ReceiptSectionState extends ConsumerState<_ReceiptSection> {
  final _headerCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  final _qrCtrl = TextEditingController();
  bool _initialised = false;

  @override
  void dispose() {
    _headerCtrl.dispose();
    _footerCtrl.dispose();
    _qrCtrl.dispose();
    super.dispose();
  }

  void _populate(ReceiptSettings s) {
    if (_initialised) return;
    _headerCtrl.text = s.headerText;
    _footerCtrl.text = s.footerText;
    _qrCtrl.text = s.qrCodeData;
    _initialised = true;
  }

  Future<void> _save() async {
    final current = ref.read(receiptSettingsProvider).valueOrNull ??
        const ReceiptSettings();
    await ref.read(receiptSettingsProvider.notifier).save(current.copyWith(
          headerText: _headerCtrl.text,
          footerText: _footerCtrl.text,
          qrCodeData: _qrCtrl.text.trim(),
        ));
    if (mounted) _showSnack('Receipt settings saved.');
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(receiptSettingsProvider);
    settingsAsync.whenData(_populate);
    final settings =
        settingsAsync.valueOrNull ?? const ReceiptSettings();

    return _SectionScaffold(
      title: 'Receipt',
      action: _SaveBtn(onPressed: _save),
      children: [
        _Card(
          title: 'CONTENT',
          children: [
            _Field(
              label: 'Header Text',
              controller: _headerCtrl,
              hint: 'Printed below the logo',
              maxLines: 3,
            ),
            _Field(
              label: 'Footer Text',
              controller: _footerCtrl,
              hint: 'Printed at the bottom of the receipt',
              maxLines: 3,
            ),
          ],
        ),
        _Card(
          title: 'DISPLAY OPTIONS',
          children: [
            _Toggle(
              label: 'Show logo on receipt',
              value: settings.showLogo,
              onChanged: (v) => ref
                  .read(receiptSettingsProvider.notifier)
                  .update((s) => s.copyWith(showLogo: v)),
            ),
            _Toggle(
              label: 'Show QR code on receipt',
              subtitle: 'E.g. link to Google Reviews or website',
              value: settings.showQrCode,
              onChanged: (v) => ref
                  .read(receiptSettingsProvider.notifier)
                  .update((s) => s.copyWith(showQrCode: v)),
            ),
            if (settings.showQrCode) ...[
              const SizedBox(height: 8),
              _Field(
                label: 'QR Code Data (URL or text)',
                controller: _qrCtrl,
                hint: 'https://g.page/r/your-restaurant',
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 5. TAX SECTION
// ---------------------------------------------------------------------------

class _TaxSection extends ConsumerStatefulWidget {
  const _TaxSection();

  @override
  ConsumerState<_TaxSection> createState() => _TaxSectionState();
}

class _TaxSectionState extends ConsumerState<_TaxSection> {
  final _standardCtrl = TextEditingController();
  final _accommodationCtrl = TextEditingController();
  final _reducedCtrl = TextEditingController();
  DateTime? _effectiveFrom;
  bool _initialised = false;

  @override
  void dispose() {
    _standardCtrl.dispose();
    _accommodationCtrl.dispose();
    _reducedCtrl.dispose();
    super.dispose();
  }

  void _populate(TaxSettings s) {
    if (_initialised) return;
    _standardCtrl.text = s.standardRate.toString();
    _accommodationCtrl.text = s.accommodationRate.toString();
    _reducedCtrl.text = s.reducedRate.toString();
    _effectiveFrom = s.effectiveFrom;
    _initialised = true;
  }

  Future<void> _pickEffectiveFrom() async {
    final current = _effectiveFrom ?? TaxSettings.defaultEffectiveFrom;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Effective-from date for this rate set',
    );
    if (picked != null) setState(() => _effectiveFrom = picked.toUtc());
  }

  Future<void> _save() async {
    final current =
        ref.read(taxSettingsProvider).valueOrNull ?? TaxSettings();
    await ref.read(taxSettingsProvider.notifier).save(current.copyWith(
          standardRate: double.tryParse(_standardCtrl.text) ??
              TaxSettings.defaultStandardRate,
          accommodationRate: double.tryParse(_accommodationCtrl.text) ??
              TaxSettings.defaultAccommodationRate,
          reducedRate: double.tryParse(_reducedCtrl.text) ??
              TaxSettings.defaultReducedRate,
          effectiveFrom: _effectiveFrom ?? TaxSettings.defaultEffectiveFrom,
        ));
    if (mounted) _showSnack('Tax settings saved.');
  }

  Future<void> _resetDefaults() async {
    await ref.read(taxSettingsProvider.notifier).resetToSwissDefaults();
    setState(() {
      _standardCtrl.text = TaxSettings.defaultStandardRate.toString();
      _accommodationCtrl.text =
          TaxSettings.defaultAccommodationRate.toString();
      _reducedCtrl.text = TaxSettings.defaultReducedRate.toString();
      _effectiveFrom = TaxSettings.defaultEffectiveFrom;
    });
    if (mounted) _showSnack('Reset to Swiss MWST defaults (01.01.2024).');
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(taxSettingsProvider);
    settingsAsync.whenData(_populate);
    final settings = settingsAsync.valueOrNull ?? TaxSettings();

    return _SectionScaffold(
      title: 'Tax (MWST)',
      action: _SaveBtn(onPressed: _save),
      children: [
        _Card(
          title: 'SWISS MWST RATES',
          children: [
            const Text(
              'These rates are defined by Swiss federal law. '
              'Only modify if the law changes.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            // Effective-from date picker
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Effective-from date',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'All three rates in this set became effective on this date.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: _pickEffectiveFrom,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.bgInput,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 14, color: AppColors.textDim),
                        const SizedBox(width: 8),
                        Text(
                          _effectiveFrom != null
                              ? '${_effectiveFrom!.year}-'
                                  '${_effectiveFrom!.month.toString().padLeft(2, '0')}-'
                                  '${_effectiveFrom!.day.toString().padLeft(2, '0')}'
                              : '—',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _RateField(
              label: 'Standard Rate (Normalsatz)',
              subtitle:
                  'Most goods & services, dine-in meals with service',
              controller: _standardCtrl,
              defaultRate: TaxSettings.defaultStandardRate,
            ),
            _RateField(
              label: 'Accommodation Rate (Beherbergungssatz)',
              subtitle: 'Hotel stays, accommodation services',
              controller: _accommodationCtrl,
              defaultRate: TaxSettings.defaultAccommodationRate,
            ),
            _RateField(
              label: 'Reduced Rate (Sondersatz)',
              subtitle:
                  'Takeaway food, non-alcoholic drinks, books, medicines',
              controller: _reducedCtrl,
              defaultRate: TaxSettings.defaultReducedRate,
            ),
          ],
        ),
        _Card(
          title: 'BEHAVIOUR',
          children: [
            _Toggle(
              label: 'Prices are tax-inclusive (gross)',
              subtitle:
                  'When enabled, MWST is extracted from the listed price',
              value: settings.taxIncludedInPrice,
              onChanged: (v) => ref
                  .read(taxSettingsProvider.notifier)
                  .update((s) => s.copyWith(taxIncludedInPrice: v)),
            ),
            _Toggle(
              label: 'Rappen rounding for cash payments',
              subtitle:
                  'Round to nearest CHF 0.05 (no 1- or 2-Rappen coins)',
              value: settings.rappenRounding,
              onChanged: (v) => ref
                  .read(taxSettingsProvider.notifier)
                  .update((s) => s.copyWith(rappenRounding: v)),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _OutlineBtn(
            label: 'Reset to Swiss defaults',
            icon: Icons.restore_rounded,
            onPressed: _resetDefaults,
          ),
        ),
      ],
    );
  }
}

class _RateField extends StatelessWidget {
  const _RateField({
    required this.label,
    required this.subtitle,
    required this.controller,
    required this.defaultRate,
  });

  final String label;
  final String subtitle;
  final TextEditingController controller;
  final double defaultRate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 90,
            child: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                suffixText: '%',
                suffixStyle: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: AppColors.bgInput,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppColors.borderFocused,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. APPEARANCE SECTION
// ---------------------------------------------------------------------------

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.valueOrNull ?? const AppSettings();

    return _SectionScaffold(
      title: l10n.settingsAppearance,
      children: [
        _Card(
          title: l10n.settingsTheme.toUpperCase(),
          children: [
            RadioGroup<AppThemeMode>(
              groupValue: settings.themeMode,
              onChanged: (v) { if (v != null) ref.read(appSettingsProvider.notifier).setTheme(v); },
              child: Column(
                children: AppThemeMode.values
                    .map(
                      (mode) => RadioListTile<AppThemeMode>(
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Icon(
                              switch (mode) {
                                AppThemeMode.dark => Icons.dark_mode_rounded,
                                AppThemeMode.light => Icons.light_mode_rounded,
                                AppThemeMode.system =>
                                  Icons.brightness_auto_rounded,
                              },
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              mode.label,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        value: mode,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
        _Card(
          title: l10n.settingsLanguage.toUpperCase(),
          children: [
            Text(
              'DE / FR / IT / EN — Schweiz (${l10n.settingsLanguage})',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            RadioGroup<AppLanguage>(
              groupValue: settings.language,
              onChanged: (v) { if (v != null) ref.read(appSettingsProvider.notifier).setLanguage(v); },
              child: Column(
                children: AppLanguage.values
                    .map(
                      (lang) => RadioListTile<AppLanguage>(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${lang.flag}  ${lang.label}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        value: lang,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 7. BACKUP SECTION
// ---------------------------------------------------------------------------

class _BackupSection extends ConsumerWidget {
  const _BackupSection();

  static final _dtFormat = DateFormat('dd.MM.yyyy HH:mm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opState = ref.watch(backupOperationProvider);
    final backupsAsync = ref.watch(backupListProvider);
    final notifier = ref.read(backupOperationProvider.notifier);

    final isBusy = opState is BackupOpBusy;

    return _SectionScaffold(
      title: 'Backup & Restore',
      children: [
        // ── Info ──────────────────────────────────────────────────────────
        _Card(
          title: 'ABOUT',
          children: [
            const Text(
              'Backups are full copies of the SQLite database stored in '
              'Documents/GastroCore/backups/. Up to 30 backups are kept; '
              'the oldest are deleted automatically.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),

        // ── Operation feedback ────────────────────────────────────────────
        if (opState is! BackupOpIdle) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: opState is BackupOpError ? AppColors.redDim : AppColors.greenDim,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                if (opState is BackupOpBusy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                else
                  Icon(
                    opState is BackupOpError ? Icons.error_rounded : Icons.check_circle_rounded,
                    size: 16,
                    color: opState is BackupOpError ? AppColors.red : AppColors.green,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    switch (opState) {
                      BackupOpBusy(message: final m) => m,
                      BackupOpSuccess(message: final m) => m,
                      BackupOpError(message: final m) => m,
                      _ => '',
                    },
                    style: TextStyle(
                      fontSize: 13,
                      color: opState is BackupOpError ? AppColors.red : AppColors.green,
                    ),
                  ),
                ),
                if (opState is! BackupOpBusy)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textDim),
                    onPressed: notifier.reset,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
        ],

        // ── Actions ───────────────────────────────────────────────────────
        _Card(
          title: 'MANUAL BACKUP',
          children: [
            _SaveBtn(
              label: isBusy ? 'Working…' : 'Create Backup Now',
              onPressed: isBusy ? null : notifier.createBackup,
            ),
          ],
        ),

        // ── Backup list ───────────────────────────────────────────────────
        _Card(
          title: 'SAVED BACKUPS',
          children: [
            backupsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              ),
              error: (e, _) => Text('Error: $e', style: const TextStyle(color: AppColors.red)),
              data: (backups) => backups.isEmpty
                  ? const Text(
                      'No backups yet. Tap "Create Backup Now" or close a shift to generate one automatically.',
                      style: TextStyle(fontSize: 13, color: AppColors.textDim),
                    )
                  : Column(
                      children: backups
                          .map((b) => _BackupTile(
                                backup: b,
                                dtFormat: _dtFormat,
                                isBusy: isBusy,
                                onRestore: () => _confirmRestore(context, ref, b),
                                onDelete: () => _confirmDelete(context, ref, b),
                              ))
                          .toList(),
                    ),
            ),
          ],
        ),

        // ── Warning ───────────────────────────────────────────────────────
        _Card(
          title: 'WARNING',
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.orange, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Restoring a backup will overwrite ALL current data. '
                    'This action cannot be undone. The app must be restarted after a restore.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmRestore(
    BuildContext context,
    WidgetRef ref,
    BackupInfo backup,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: const Text('Restore Backup?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'This will overwrite ALL current data with "${backup.name}".\n\nThis cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: AppColors.surfaceDim,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(backupOperationProvider.notifier).restoreBackup(backup);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    BackupInfo backup,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: const Text('Delete Backup?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Delete "${backup.name}" (${backup.sizeLabel})?\nThis cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: AppColors.surfaceDim,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(backupOperationProvider.notifier).deleteBackup(backup);
    }
  }
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({
    required this.backup,
    required this.dtFormat,
    required this.isBusy,
    required this.onRestore,
    required this.onDelete,
  });

  final BackupInfo backup;
  final DateFormat dtFormat;
  final bool isBusy;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.storage_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dtFormat.format(backup.createdAt),
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  backup.sizeLabel,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: isBusy ? null : onRestore,
            child: const Text('Restore', style: TextStyle(fontSize: 12, color: AppColors.primary)),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.red),
            onPressed: isBusy ? null : onDelete,
            tooltip: 'Delete',
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(6),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7b. AUDIT LOG (link to dedicated screen)
// ---------------------------------------------------------------------------

class _AuditLogLinkSection extends StatelessWidget {
  const _AuditLogLinkSection({required this.onNavigate});
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return _SectionScaffold(
      title: 'Audit Log',
      children: [
        _Card(
          children: [
            const Text(
              'A full record of all auditable events — orders, payments, '
              'voids, discounts, logins, shift changes, and settings. '
              'Visible to admin and manager roles only.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => context.push(AppRoutes.auditLog),
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text('Open Audit Log'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.surfaceDim,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// UPGRADE / LICENSE SECTION
// ---------------------------------------------------------------------------

class _UpgradeSection extends ConsumerStatefulWidget {
  const _UpgradeSection();

  @override
  ConsumerState<_UpgradeSection> createState() => _UpgradeSectionState();
}

class _UpgradeSectionState extends ConsumerState<_UpgradeSection> {
  final _tokenCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      setState(() {
        _error = 'Please paste your license token.';
        _success = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      final entity =
          await ref.read(licenseNotifierProvider.notifier).activate(token);
      if (mounted) {
        setState(() {
          _success =
              'License activated — ${entity.tier.displayName} tier until '
              '${DateFormat('dd MMM yyyy').format(entity.expiresAt)}';
          _tokenCtrl.clear();
        });
      }
    } on LicenseException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Activation failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deactivate() async {
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      await ref.read(licenseNotifierProvider.notifier).deactivate();
      if (mounted) setState(() => _success = 'License removed. Reverted to Free tier.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to remove license: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final licenseAsync = ref.watch(currentLicenseProvider);
    final tier = ref.watch(licenseTierProvider);

    return _SectionScaffold(
      title: 'License & Upgrade',
      children: [
        // Current status card
        _Card(
          title: 'CURRENT STATUS',
          children: [
            Row(
              children: [
                LicenseBadge(),
                const SizedBox(width: 12),
                licenseAsync.when(
                  data: (license) {
                    if (license == null) {
                      return const Text(
                        'No license activated — Free tier is active.',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 14),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${license.tier.displayName} — ${license.businessId}',
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          license.isExpired
                              ? license.isInGracePeriod
                                  ? 'Expired — ${license.daysUntilDowngrade}d grace remaining'
                                  : 'Expired — downgraded to Free'
                              : 'Expires ${DateFormat('dd MMM yyyy').format(license.expiresAt)}',
                          style: TextStyle(
                            color: license.isExpired
                                ? AppColors.red
                                : AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => const Text('Failed to load license',
                      style: TextStyle(color: AppColors.red, fontSize: 13)),
                ),
              ],
            ),
            if (licenseAsync.valueOrNull != null && !_loading) ...[
              const SizedBox(height: 12),
              _TextBtn(
                label: 'Remove license',
                onTap: _deactivate,
              ),
            ],
          ],
        ),

        // Feature matrix
        _Card(
          title: 'FEATURE COMPARISON',
          children: [
            _FeatureMatrix(currentTier: tier),
          ],
        ),

        // Activate / upgrade card
        _Card(
          title: 'ACTIVATE LICENSE',
          children: [
            const Text(
              'Paste the license token you received after purchase:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenCtrl,
              maxLines: 3,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'eyJ2IjoxLCJidXNpbmVzc0lk…',
                hintStyle: const TextStyle(color: AppColors.textDim),
                filled: true,
                fillColor: AppColors.surfaceDim,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_rounded,
                      color: AppColors.textDim, size: 18),
                  tooltip: 'Paste from clipboard',
                  onPressed: () async {
                    final data =
                        await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) _tokenCtrl.text = data!.text!;
                  },
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!,
                  style: const TextStyle(
                      color: AppColors.red, fontSize: 12)),
            ],
            if (_success != null) ...[
              const SizedBox(height: 6),
              Text(_success!,
                  style: const TextStyle(
                      color: Color(0xFF4CAF50), fontSize: 12)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _activate,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.workspace_premium_rounded, size: 18),
              label: const Text('Activate License'),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Feature comparison matrix
// ---------------------------------------------------------------------------

class _FeatureMatrix extends StatelessWidget {
  const _FeatureMatrix({required this.currentTier});

  final LicenseTier currentTier;

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
      },
      children: [
        // Header row
        TableRow(
          decoration: const BoxDecoration(
            border: Border(
                bottom: BorderSide(color: AppColors.surfaceContainerHigh)),
          ),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Feature',
                  style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
            for (final tier in LicenseTier.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Center(
                  child: Text(
                    tier.badge,
                    style: TextStyle(
                      color: tier == currentTier
                          ? _tierColor(tier)
                          : AppColors.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        // Feature rows
        ...AppFeature.values.map((f) => _featureRow(f, currentTier)),
      ],
    );
  }

  TableRow _featureRow(AppFeature feature, LicenseTier currentTier) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            feature.displayName,
            style: TextStyle(
              color: currentTier.isAtLeast(feature.requiredTier)
                  ? AppColors.textPrimary
                  : AppColors.textDim,
              fontSize: 13,
            ),
          ),
        ),
        for (final tier in LicenseTier.values)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: tier.isAtLeast(feature.requiredTier)
                  ? Icon(Icons.check_rounded,
                      size: 16,
                      color: tier == currentTier
                          ? _tierColor(tier)
                          : AppColors.textDim)
                  : const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }

  Color _tierColor(LicenseTier tier) => switch (tier) {
        LicenseTier.free => AppColors.textDim,
        LicenseTier.starter => const Color(0xFF4CAF50),
        LicenseTier.professional => const Color(0xFF4C9EFF),
        LicenseTier.enterprise => const Color(0xFFB06EFF),
      };
}

// ---------------------------------------------------------------------------
// 8. ABOUT SECTION
// ---------------------------------------------------------------------------

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return _SectionScaffold(
      title: 'About',
      children: [
        _Card(
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.restaurant_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GastroCore POS',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Version 0.1.0 (build 1)',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        _Card(
          title: 'MARKET',
          children: const [
            _AboutRow(
              label: 'Target market',
              value: 'Switzerland 🇨🇭',
            ),
            _AboutRow(label: 'Currency', value: 'CHF (Swiss Franc)'),
            _AboutRow(
              label: 'VAT authority',
              value: 'ESTV / AFC / AFC',
            ),
            _AboutRow(
              label: 'VAT standard rate',
              value: '8.1% (since 01.01.2024)',
            ),
            _AboutRow(
              label: 'Payment protocols',
              value: 'Wallee LTI · MyPOS',
            ),
          ],
        ),
        _Card(
          title: 'TECHNICAL',
          children: const [
            _AboutRow(label: 'Framework', value: 'Flutter 3.x'),
            _AboutRow(label: 'Database', value: 'SQLite (Drift ORM)'),
            _AboutRow(label: 'State management', value: 'Riverpod 2.6'),
            _AboutRow(label: 'Navigation', value: 'GoRouter 14'),
            _AboutRow(label: 'Print protocol', value: 'ESC/POS'),
          ],
        ),
        _Card(
          title: 'LICENSE',
          children: const [
            Text(
              'Copyright © 2024–2026 2TechHub\n\n'
              'All rights reserved. Unauthorised reproduction or '
              'distribution of this software, or any portion of it, '
              'may result in severe civil and criminal penalties.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class _GastroCoreLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Gastro',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryContainer],
          ).createShader(bounds),
          child: const Text(
            'Core',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.textPrimary.withValues(alpha: 0.06),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 22, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _TextBtn extends StatelessWidget {
  const _TextBtn({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.textPrimary.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  const _OutlineBtn({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon != null
          ? Icon(icon, size: 16)
          : const SizedBox.shrink(),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        side: const BorderSide(color: AppColors.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _SegmentedRow<T> extends StatelessWidget {
  const _SegmentedRow({
    required this.values,
    required this.current,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final T current;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: values.map((v) {
        final selected = v == current;
        return GestureDetector(
          onTap: () => onChanged(v),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? AppColors.primary
                    : AppColors.outlineVariant,
              ),
            ),
            child: Text(
              labelOf(v),
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Reports Section
// ---------------------------------------------------------------------------

class _ReportsSection extends ConsumerWidget {
  const _ReportsSection({required this.onNavigate});
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Role gate: Z-Bericht / X-Rapor requires Yönetici (admin).
    final canZReport = ref.watch(canProvider(Permission.zReport));
    return _SectionScaffold(
      title: 'Raporlar',
      children: [
        _Card(
          title: 'Z-Raporu (Tagesabschluss)',
          children: [
            const Text(
              'Z-Raporu (gün sonu): cari vardiyanın cirosunu, ödemelerini, '
              'KDV/MwSt dökümünü ve en çok satan ürünleri gösterir. '
              'Aynı ekrandan X-Raporu (ara rapor, kasa sıfırlanmaz) da '
              'yazdırılabilir.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Tooltip(
                message: canZReport ? '' : kPermissionRequiredTooltip,
                child: ElevatedButton.icon(
                  key: const Key('settings_open_z_report'),
                  onPressed: canZReport
                      ? () {
                          context.push(AppRoutes.zReport);
                        }
                      : null,
                  icon: const Icon(Icons.assessment_rounded, size: 18),
                  label: const Text('Z-Raporu aç'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.surfaceDim,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: canZReport ? '' : kPermissionRequiredTooltip,
                child: OutlinedButton.icon(
                  key: const Key('settings_open_x_report'),
                  onPressed: canZReport
                      ? () {
                          // X-Raporu aynı Z-Raporu ekranından yazdırılır
                          // (Zwischenbericht — kasa sıfırlama yok).
                          context.push(AppRoutes.zReport);
                        }
                      : null,
                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                  label: const Text('X-Raporu (ara rapor)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.orange,
                    side: const BorderSide(color: AppColors.orange),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
        _Card(
          title: 'Vardiya Geçmişi',
          children: [
            const Text(
              'Tüm geçmiş vardiyalar, ciroları ve kasa bakiyesiyle birlikte.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                context.push(AppRoutes.shiftHistory);
              },
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text('Vardiya geçmişi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surfaceContainerHigh,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        _Card(
          title: 'Gün Sonu / Kassensturz',
          children: [
            const Text(
              'Vardiyayı kapat, kasayı say ve Z-Raporu yazdır.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              key: const Key('settings_open_day_close'),
              onPressed: () {
                context.go(AppRoutes.dayClose);
              },
              icon: const Icon(Icons.lock_clock_rounded, size: 18),
              label: const Text('Gün sonunu başlat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orangeDim,
                foregroundColor: AppColors.orange,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Demo Data Section
// ---------------------------------------------------------------------------

class _DemoDataSection extends ConsumerStatefulWidget {
  const _DemoDataSection();

  @override
  ConsumerState<_DemoDataSection> createState() => _DemoDataSectionState();
}

class _DemoDataSectionState extends ConsumerState<_DemoDataSection> {
  bool _busy = false;

  Future<void> _loadDemo() async {
    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      await SeedData(db).seedForce();
      if (mounted) _showSnack('Demo veriler başarıyla yüklendi.');
    } catch (e) {
      if (mounted) _showSnack('Hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearDemo() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: const Text(
          'Demo Veriyi Temizle',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Tüm demo veriler (ürünler, siparişler, personel dahil) '
          'kalıcı olarak silinecektir. Devam edilsin mi?',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'İptal',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Temizle',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      await SeedData(db).clearAll();
      if (mounted) _showSnack('Demo veriler temizlendi.');
    } catch (e) {
      if (mounted) _showSnack('Hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionScaffold(
      title: 'Demo Data',
      children: [
        _Card(
          title: 'DEMO VERİLER',
          children: [
            const Text(
              'Restoran için hazır örnek menü, personel, masa düzeni ve '
              'İsviçre vergi profilleri yükler. Mevcut veriler silinip '
              'yeniden oluşturulur.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            if (_busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _OutlineBtn(
                    label: 'Demo Veri Yükle',
                    icon: Icons.download_rounded,
                    onPressed: _loadDemo,
                  ),
                  OutlinedButton.icon(
                    onPressed: _clearDemo,
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Demo Veriyi Temizle'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        _Card(
          title: 'DEMO PERSONEL — PIN KODLARI',
          children: [
            _DemoStaffRow('Max Müller', 'Manager', '1234'),
            _DemoStaffRow('Sarah Weber', 'Kellnerin', '5678'),
            _DemoStaffRow('Luca Bernasconi', 'Koch', '9012'),
            _DemoStaffRow('Anna Fischer', 'Kassiererin', '3456'),
            _DemoStaffRow('Mehmet Yılmaz', 'Kellner', '7890'),
          ],
        ),
      ],
    );
  }
}

class _DemoStaffRow extends StatelessWidget {
  const _DemoStaffRow(this.name, this.role, this.pin);

  final String name;
  final String role;
  final String pin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              role,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'PIN: $pin',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Snackbar helper (extension on ConsumerState)
// ---------------------------------------------------------------------------

extension on ConsumerState {
  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.surfaceContainerHigh,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Access-denied placeholder
// ---------------------------------------------------------------------------

/// Shown in place of the settings sidebar/content when the current user's
/// role lacks [Permission.settings]. Greyed out rather than hidden so staff
/// see the feature exists and can ask a manager for access.
class _AccessDeniedPane extends StatelessWidget {
  const _AccessDeniedPane();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(
        opacity: 0.55,
        child: Tooltip(
          message: kPermissionRequiredTooltip,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.lock_outline_rounded,
                size: 48,
                color: AppColors.textSecondary,
              ),
              SizedBox(height: 12),
              Text(
                'Yetki gerekli',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Ayarları yalnızca Yönetici açabilir.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
