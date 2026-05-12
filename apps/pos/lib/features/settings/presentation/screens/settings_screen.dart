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
import 'package:gastrocore_pos/features/settings/domain/entities/loyalty_settings.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/ecocash/ecocash_client.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/mypos/mypos_client.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/payment_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/printer_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/receipt_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/tax_settings.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/action_buttons/domain/entities/action_button_entity.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/features/action_buttons/presentation/providers/action_button_provider.dart';
import 'package:gastrocore_pos/features/gang/presentation/providers/gang_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/theme/pos_v2_theme.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/theme_customization.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/favorites_bar.dart';
import 'package:gastrocore_pos/core/services/backup_service.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/permission.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/fast_sale/domain/restaurant_config.dart';
import 'package:gastrocore_pos/features/fast_sale/presentation/providers/restaurant_config_provider.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/backup_provider.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';
import 'package:gastrocore_pos/features/settings/presentation/widgets/network_status_pane.dart';
import 'package:gastrocore_pos/features/settings/presentation/widgets/tenant_switcher_pane.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/update_channel_settings.dart';
import 'package:gastrocore_pos/features/updates/domain/app_version.dart';
import 'package:gastrocore_pos/features/updates/domain/entities/update_manifest.dart';
import 'package:gastrocore_pos/features/updates/presentation/providers/update_provider.dart';
import 'package:gastrocore_pos/features/sync/domain/entities/sync_event_entity.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';
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
  posMode('POS Modu', Icons.flash_on_rounded),
  printer('Printer', Icons.print_rounded),
  payment('Payment', Icons.payment_rounded),
  receipt('Receipt', Icons.receipt_long_rounded),
  tax('Tax (MWST)', Icons.calculate_rounded),
  favorites('Hızlı Erişim Butonları', Icons.star_rounded),
  functionButtons('Fonksiyon Butonları', Icons.flash_on_rounded),
  reports('Reports', Icons.assessment_rounded),
  appearance('Appearance', Icons.palette_rounded),
  themeColors('Tema Renkleri', Icons.color_lens_rounded),
  backup('Backup & Restore', Icons.backup_rounded),
  auditLog('Audit Log', Icons.history_rounded),
  loyalty('Treueprogramm', Icons.card_giftcard_rounded),
  demoData('Demo Data', Icons.science_outlined),
  tenantSwitcher('Mağaza Seçici', Icons.store_rounded),
  networkStatus('Bağlantı Durumu', Icons.wifi_find_rounded),
  upgrade('License & Upgrade', Icons.workspace_premium_rounded),
  updates('Güncelleme', Icons.system_update_alt_rounded),
  syncDlq('Senkron DLQ', Icons.error_outline_rounded),
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
    // Settings is opened from the POS sales shell; the user always wants
    // to land back on `/pos`, not the analytics dashboard at `/home`.
    // If the router has a closer entry on the stack we still pop first
    // (preserves modal nesting), otherwise we go straight to POS.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.pos);
    }
  }

  Widget _buildContent() {
    return switch (_selected) {
      _Section.restaurant => const _RestaurantSection(),
      _Section.posMode => const _PosModeSection(),
      _Section.printer => const _PrinterSection(),
      _Section.payment => const _PaymentSection(),
      _Section.receipt => const _ReceiptSection(),
      _Section.tax => const _TaxSection(),
      _Section.favorites => const _FavoritesSection(),
      _Section.functionButtons => const _FunctionButtonsSection(),
      _Section.reports => _ReportsSection(onNavigate: _navigateBack),
      _Section.appearance => const _AppearanceSection(),
      _Section.themeColors => const _ThemeColorsSection(),
      _Section.backup => const _BackupSection(),
      _Section.auditLog => _AuditLogLinkSection(onNavigate: _navigateBack),
      _Section.loyalty => const _LoyaltySection(),
      _Section.demoData => const _DemoDataSection(),
      _Section.tenantSwitcher => const TenantSwitcherPane(),
      _Section.networkStatus => const NetworkStatusPane(),
      _Section.upgrade => const _UpgradeSection(),
      _Section.updates => const _UpdatesSection(),
      _Section.syncDlq => const _SyncDlqSection(),
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
    final l10n = AppLocalizations.of(context);
    final backLabel = l10n.settingsBackToPos;
    return Container(
      height: 56,
      color: AppColors.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Leading icon-only back button — preserves the original
          // affordance for users who learnt to look top-left.
          Semantics(
            button: true,
            label: backLabel,
            child: _IconBtn(icon: Icons.arrow_back_rounded, onTap: onBack),
          ),
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
          // Trailing labelled button — explicit "Zurück zum POS" /
          // "POS'a Dön" so operators know exactly where Back lands them.
          Semantics(
            button: true,
            label: backLabel,
            child: _TextBtn(label: backLabel, onTap: onBack),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sidebar
// ---------------------------------------------------------------------------

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.selected, required this.onSelect});

  final _Section selected;
  final ValueChanged<_Section> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The runtime tenant switcher tile only appears when the operator
    // (or remote config) has flipped multiTenantSwitcherEnabled. The
    // flag's default-false keeps pilot devices identical to the pre-
    // multi-tenant build. While the AsyncValue is loading we hide the
    // tile too — preferring not-shown to a flicker.
    final settingsAsync = ref.watch(appSettingsProvider);
    final showTenantSwitcher = settingsAsync.maybeWhen(
      data: (s) => s.multiTenantSwitcherEnabled,
      orElse: () => false,
    );

    final visible = _Section.values.where((s) {
      if (s == _Section.tenantSwitcher && !showTenantSwitcher) return false;
      return true;
    });

    return Container(
      width: 220,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SingleChildScrollView(
        child: Column(
          children: visible
              .map(
                (s) => _SidebarItem(
                  section: s,
                  isSelected: s == selected,
                  onTap: () => onSelect(s),
                ),
              )
              .toList(),
        ),
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
    // Use copyWith so identity edits don't clobber operator preferences
    // owned by other tabs (gang toggles, temporary-table flag, shift
    // policy …). Falling back to a fresh entity if the repo hasn't
    // loaded yet matches the pre-2026-04-23 behaviour.
    final current = ref.read(restaurantSettingsProvider).valueOrNull ??
        const RestaurantSettings();
    await notifier.save(current.copyWith(
      name: _nameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      mwstNr: _mwstCtrl.text.trim(),
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
            _Toggle(
              label: 'Per-gang fire chip',
              subtitle:
                  'When off (pilot default) the global "Senden" footer '
                  'sends every unsent item in one tap. Turn on for '
                  'fine-dining workflows that fire each course on its '
                  'own timer; the GÖNDER chip then reappears next to '
                  'every gang section.',
              value:
                  settingsAsync.valueOrNull?.enablePerGangFire ?? false,
              onChanged: (v) => ref
                  .read(restaurantSettingsProvider.notifier)
                  .update((s) => s.copyWith(enablePerGangFire: v)),
            ),
            _Toggle(
              label: 'Allow temporary tables',
              subtitle:
                  'Lets cashiers spin up an ad-hoc table from the sales '
                  'shell — type "150" on the numpad, ring up the round, '
                  'and the table disappears once the bill is paid. '
                  'Turn off to lock the table list to the floor plan.',
              value: settingsAsync.valueOrNull?.allowTemporaryTables ??
                  true,
              onChanged: (v) => ref
                  .read(restaurantSettingsProvider.notifier)
                  .update((s) => s.copyWith(allowTemporaryTables: v)),
            ),
            const SizedBox(height: 8),
            const Text(
              'PRODUCT TILE SIZE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            _PosTileSizeControls(
              scale: (settingsAsync.valueOrNull?.posTileScale ?? 1.0)
                  .clamp(0.7, 1.5)
                  .toDouble(),
              mode: settingsAsync.valueOrNull?.posTileMode ??
                  PosTileMode.fixed,
              onScaleChanged: (next) => ref
                  .read(restaurantSettingsProvider.notifier)
                  .update((s) => s.copyWith(posTileScale: next)),
              onModeChanged: (next) => ref
                  .read(restaurantSettingsProvider.notifier)
                  .update((s) => s.copyWith(posTileMode: next)),
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
  final _myposLangCtrl = TextEditingController();
  final _myposMerchantCtrl = TextEditingController();
  final _myposTerminalCtrl = TextEditingController();
  bool _myposTesting = false;
  String? _myposTestResult;
  final _ccBaseUrlCtrl = TextEditingController();
  final _ccDeviceIdCtrl = TextEditingController();
  final _ccClientIdCtrl = TextEditingController();
  final _ccTokenPassCtrl = TextEditingController();
  final _ccCurrencyCtrl = TextEditingController();
  bool _ccTesting = false;
  String? _ccTestResult;
  bool _initialised = false;

  @override
  void dispose() {
    _walleeIpCtrl.dispose();
    _walleePortCtrl.dispose();
    _walleePosIdCtrl.dispose();
    _myposIpCtrl.dispose();
    _myposPortCtrl.dispose();
    _myposCurrencyCtrl.dispose();
    _myposLangCtrl.dispose();
    _myposMerchantCtrl.dispose();
    _myposTerminalCtrl.dispose();
    _ccBaseUrlCtrl.dispose();
    _ccDeviceIdCtrl.dispose();
    _ccClientIdCtrl.dispose();
    _ccTokenPassCtrl.dispose();
    _ccCurrencyCtrl.dispose();
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
    _myposLangCtrl.text = s.mypos.language;
    _myposMerchantCtrl.text = s.mypos.merchantId;
    _myposTerminalCtrl.text = s.mypos.terminalId;
    _ccBaseUrlCtrl.text = s.cashCollector.baseUrl;
    _ccDeviceIdCtrl.text = s.cashCollector.deviceId;
    _ccClientIdCtrl.text = s.cashCollector.clientId;
    _ccTokenPassCtrl.text = s.cashCollector.tokenPass;
    _ccCurrencyCtrl.text = s.cashCollector.currency;
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
          mypos: current.mypos.copyWith(
            ip: _myposIpCtrl.text.trim(),
            port: int.tryParse(_myposPortCtrl.text.trim()) ?? 60180,
            currency: _myposCurrencyCtrl.text.trim().toUpperCase(),
            language: _myposLangCtrl.text.trim().toLowerCase(),
            merchantId: _myposMerchantCtrl.text.trim(),
            terminalId: _myposTerminalCtrl.text.trim(),
          ),
          cashCollector: current.cashCollector.copyWith(
            baseUrl: _ccBaseUrlCtrl.text.trim(),
            deviceId: _ccDeviceIdCtrl.text.trim(),
            clientId: _ccClientIdCtrl.text.trim(),
            tokenPass: _ccTokenPassCtrl.text.trim(),
            currency: _ccCurrencyCtrl.text.trim().toUpperCase(),
          ),
        ));
    if (mounted) _showSnack('Payment settings saved.');
  }

  /// Probes the MyPOS Sigma terminal: opens a fresh client with the
  /// fields currently in the form, runs configure+connect, and ping
  /// the terminal. Cleans up afterwards (best-effort disconnect).
  Future<void> _testMyPos() async {
    setState(() {
      _myposTesting = true;
      _myposTestResult = null;
    });
    final client = MyPosClient(
      terminalIp: _myposIpCtrl.text.trim(),
      terminalPort: int.tryParse(_myposPortCtrl.text.trim()) ?? 60180,
    );
    try {
      final connected = await client.connect();
      if (!connected) {
        if (!mounted) return;
        setState(() => _myposTestResult =
            '✗ Configure başarısız. IP/Port doğru mu? Terminal açık mı?');
        return;
      }
      // SDK fires onConnectionChanged async; pingTerminal forces a round-trip
      // so we wait for a real answer instead of trusting "configured".
      final ping = await client.pingTerminal();
      if (!mounted) return;
      setState(() => _myposTestResult = ping
          ? '✓ ${_myposIpCtrl.text.trim()}:${_myposPortCtrl.text.trim()} '
              'terminal yanıt veriyor.'
          : '✗ Terminale ulaşıldı ama PING yanıt vermedi (cihaz uykuda olabilir).');
    } catch (e) {
      if (!mounted) return;
      setState(() => _myposTestResult = '✗ $e');
    } finally {
      try {
        await client.disconnect();
      } catch (_) {}
      if (mounted) setState(() => _myposTesting = false);
    }
  }

  /// Probes the kiosk by logging in and pulling /api/get/status. Updates
  /// [_ccTestResult] with a short message — no other state changes, so the
  /// operator can run it before saving to validate the inputs first.
  Future<void> _testCashCollector() async {
    setState(() {
      _ccTesting = true;
      _ccTestResult = null;
    });
    final client = EcoCashClient(EcoCashConfig(
      baseUrl: _ccBaseUrlCtrl.text.trim(),
      deviceId: _ccDeviceIdCtrl.text.trim(),
      clientId: _ccClientIdCtrl.text.trim(),
      tokenPass: _ccTokenPassCtrl.text.trim(),
      currency: _ccCurrencyCtrl.text.trim().toUpperCase(),
    ));
    try {
      await client.login();
      final status = await client.getStatus();
      if (!mounted) return;
      setState(() => _ccTestResult =
          '✓ ${status.deviceId} · ${status.softwareVer} · status=${status.status}');
    } on EcoCashException catch (e) {
      if (!mounted) return;
      setState(() => _ccTestResult = '✗ [${e.code}] ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _ccTestResult = '✗ $e');
    } finally {
      client.close();
      if (mounted) setState(() => _ccTesting = false);
    }
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
          title: 'MYPOS KART TERMİNALİ (Sigma)',
          children: [
            const Text(
              'Açık olduğunda, KART ve TWINT ödemeleri direkt MyPOS Sigma '
              'terminaline yönlendirilir: müşteri kartı yaklaştırır / '
              'PIN girer veya TWINT QR’ı okutur. Terminal sonucu yazınca '
              'adisyon otomatik kapanır. Kapalıyken eski manuel akış '
              '(tek-tap KART / manuel TWINT onayı) kullanılır.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            _Toggle(
              label: 'MyPOS terminalini kullan',
              subtitle:
                  'KART + TWINT seçilince ÖDE tuşu terminali tetikler',
              value: settings.mypos.enabled,
              onChanged: (v) => ref
                  .read(paymentSettingsProvider.notifier)
                  .update(
                    (s) => s.copyWith(mypos: s.mypos.copyWith(enabled: v)),
                  ),
            ),
            const SizedBox(height: 8),
            _Field(
              label: 'Terminal IP',
              controller: _myposIpCtrl,
              hint: '192.168.1.131',
            ),
            _Field(
              label: 'Port (Sigma default 60180)',
              controller: _myposPortCtrl,
              hint: '60180',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            _Field(
              label: 'Para Birimi',
              controller: _myposCurrencyCtrl,
              hint: 'CHF',
              keyboardType: TextInputType.text,
            ),
            _Field(
              label: 'Terminal Dili (de / fr / it / en)',
              controller: _myposLangCtrl,
              hint: 'de',
            ),
            _Field(
              label: 'Merchant ID (opsiyonel)',
              controller: _myposMerchantCtrl,
              hint: 'MyPOS tarafından sağlanır',
            ),
            _Field(
              label: 'Terminal ID (opsiyonel)',
              controller: _myposTerminalCtrl,
              hint: 'MyPOS tarafından sağlanır',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _myposTesting ? null : _testMyPos,
                  icon: _myposTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded, size: 16),
                  label: const Text('BAĞLANTIYI TEST ET'),
                ),
                const SizedBox(width: 12),
                if (_myposTestResult != null)
                  Expanded(
                    child: Text(
                      _myposTestResult!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _myposTestResult!.startsWith('✓')
                            ? AppColors.green
                            : AppColors.red,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        _Card(
          title: 'KASA OTOMATI (EcoCash V4.2)',
          children: [
            const Text(
              'Açık olduğunda, BAR ödeme yöntemi kasa otomatına yönlendirilir: '
              'müşteri parayı cihaza yerleştirir, cihaz para üstünü otomatik verir. '
              'Kapalıyken ödeme ekranındaki manuel nakit girişi çalışır.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            _Toggle(
              label: 'Kasa otomatını kullan',
              subtitle:
                  'BAR seçildiğinde ÖDE tuşu cihazı tetikler ve müşteriden para alır',
              value: settings.cashCollector.enabled,
              onChanged: (v) => ref
                  .read(paymentSettingsProvider.notifier)
                  .update((s) =>
                      s.copyWith(cashCollector: s.cashCollector.copyWith(enabled: v))),
            ),
            const SizedBox(height: 8),
            _Field(
              label: 'Cihaz URL',
              controller: _ccBaseUrlCtrl,
              hint: 'http://192.168.1.149:8080/',
              keyboardType: TextInputType.url,
            ),
            _Field(
              label: 'Cihaz ID (device_id)',
              controller: _ccDeviceIdCtrl,
              hint: '00141',
            ),
            _Field(
              label: 'Terminal ID (client_id)',
              controller: _ccClientIdCtrl,
              hint: '2',
            ),
            _Field(
              label: 'Token Parolası',
              controller: _ccTokenPassCtrl,
              hint: '123456 (varsayılan — değiştirin)',
            ),
            _Field(
              label: 'Para Birimi',
              controller: _ccCurrencyCtrl,
              hint: 'CHF',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _ccTesting ? null : _testCashCollector,
                  icon: _ccTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded, size: 16),
                  label: const Text('BAĞLANTIYI TEST ET'),
                ),
                const SizedBox(width: 12),
                if (_ccTestResult != null)
                  Expanded(
                    child: Text(
                      _ccTestResult!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _ccTestResult!.startsWith('✓')
                            ? AppColors.green
                            : AppColors.red,
                      ),
                    ),
                  ),
              ],
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
        _Card(
          title: 'KULLANIM ELİ',
          children: [
            const Text(
              'POS yerleşimini sağ el veya sol el için aynala. Sol el modunda '
              'şerit ve sipariş paneli sağ tarafa geçer, menü alanı sola kayar.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            RadioGroup<AppHandedness>(
              groupValue: settings.handedness,
              onChanged: (v) {
                if (v != null) {
                  ref.read(appSettingsProvider.notifier).setHandedness(v);
                }
              },
              child: Column(
                children: AppHandedness.values
                    .map(
                      (hand) => RadioListTile<AppHandedness>(
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Icon(
                              hand == AppHandedness.right
                                  ? Icons.swipe_right_alt_rounded
                                  : Icons.swipe_left_alt_rounded,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              hand.label,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        value: hand,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
        _Card(
          title: 'YÜKSEK KONTRAST',
          children: [
            const Text(
              'Açık veya koyu temanın üzerine saf siyah / beyaz bir palet '
              'bindirir. Parlak ortamlarda ve düşük görüşlü operatörler için '
              'metin, kenar ve ayırıcılar daha okunaklı olur.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Yüksek kontrast modu',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Text(
                settings.highContrast ? 'Açık' : 'Kapalı',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              value: settings.highContrast,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .setHighContrast(v),
            ),
          ],
        ),
        _Card(
          title: 'YAZI BOYUTU',
          children: [
            const Text(
              'Tüm ekranlardaki metin boyutunu ölçekler. iOS / Android '
              'erişilebilirlik ayarlarıyla aynı mantık; yazı büyüdükçe '
              'sıra yükseklikleri de otomatik büyür.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            RadioGroup<AppTextScale>(
              groupValue: settings.textScale,
              onChanged: (v) {
                if (v != null) {
                  ref.read(appSettingsProvider.notifier).setTextScale(v);
                }
              },
              child: Column(
                children: AppTextScale.values
                    .map(
                      (scale) => RadioListTile<AppTextScale>(
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Text(
                              scale.label,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '×${scale.scale.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        value: scale,
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
class _FavoritesSection extends ConsumerWidget {
  const _FavoritesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);

    return _SectionScaffold(
      title: 'Hızlı Erişim Butonları',
      action: ElevatedButton.icon(
        onPressed: () => _openEditor(context, ref, null),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Yeni Favori Ekle'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      children: [
        _Card(
          title: 'HAKKINDA',
          children: const [
            Text(
              'Bu butonlar POS satış ekranında ürün kılavuzunun üstünde '
              'yatay şerit olarak görünür. Her buton bir ürünü sepete '
              'ekleyebilir ya da bir kategoriye geçiş yapabilir. Aşağıdaki '
              'sıralama satış ekranına birebir yansır.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
        _Card(
          title: 'FAVORİLER (${favorites.length})',
          children: [
            if (favorites.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Henüz favori yok. Yukarıdaki "Yeni Favori Ekle" ile başla.',
                    style:
                        TextStyle(color: AppColors.textDim, fontSize: 13),
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: favorites.length,
                itemBuilder: (ctx, i) {
                  final fav = favorites[i];
                  return _FavoriteRow(
                    key: ValueKey(fav.id),
                    index: i,
                    favorite: fav,
                    onEdit: () => _openEditor(context, ref, fav),
                    onDelete: () => _confirmDelete(context, ref, fav),
                  );
                },
                onReorder: (oldIndex, newIndex) {
                  final ordered = favorites
                      .map((b) => b.id)
                      .toList();
                  final idx =
                      newIndex > oldIndex ? newIndex - 1 : newIndex;
                  final moved = ordered.removeAt(oldIndex);
                  ordered.insert(idx, moved);
                  ref.read(favoritesProvider.notifier).reorder(ordered);
                },
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    FavoriteButton? existing,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FavoriteEditorDialog(existing: existing),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    FavoriteButton fav,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Favoriyi sil?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          '"${fav.label}" butonu favorilerden kaldırılacak.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Sil', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(favoritesProvider.notifier).remove(fav.id);
    }
  }
}
class _FavoriteRow extends StatelessWidget {
  const _FavoriteRow({
    super.key,
    required this.index,
    required this.favorite,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final FavoriteButton favorite;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tint = favorite.color ??
        (favorite.action == FavoriteAction.addProduct
            ? AppColors.green
            : AppColors.orange);
    final icon = favorite.action == FavoriteAction.addProduct
        ? Icons.fastfood_rounded
        : Icons.category_rounded;
    final typeLabel = favorite.action == FavoriteAction.addProduct
        ? 'Ürün'
        : 'Kategori';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.drag_indicator_rounded,
                  size: 20, color: AppColors.textDim),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  favorite.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$typeLabel · ${favorite.target}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded,
                size: 18, color: AppColors.primary),
            onPressed: onEdit,
            tooltip: 'Düzenle',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                size: 18, color: AppColors.red),
            onPressed: onDelete,
            tooltip: 'Sil',
          ),
        ],
      ),
    );
  }
}

class _FavoriteEditorDialog extends ConsumerStatefulWidget {
  const _FavoriteEditorDialog({this.existing});

  final FavoriteButton? existing;

  @override
  ConsumerState<_FavoriteEditorDialog> createState() =>
      _FavoriteEditorDialogState();
}

class _FavoriteEditorDialogState
    extends ConsumerState<_FavoriteEditorDialog> {
  late FavoriteAction _action;
  late TextEditingController _label;
  late TextEditingController _search;
  String? _targetName;
  Color? _color;

  static const List<Color> _palette = [
    Color(0xFF43A047), // catGreen
    Color(0xFFF57C00), // catOrange
    Color(0xFFE53935), // catRed
    Color(0xFFFBC02D), // catYellow
    Color(0xFF00838F), // catTeal
    Color(0xFF7B1FA2), // catPurple
    Color(0xFF3841E9), // primary
    Color(0xFF2E7D32), // catDarkGreen
  ];

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _action = ex?.action ?? FavoriteAction.addProduct;
    _label = TextEditingController(text: ex?.label ?? '');
    _search = TextEditingController();
    _targetName = ex?.target;
    _color = ex?.color;
  }

  @override
  void dispose() {
    _label.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(allActiveProductsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final products = productsAsync.valueOrNull ?? const <ProductEntity>[];
    final categories =
        categoriesAsync.valueOrNull ?? const <CategoryEntity>[];

    final query = _search.text.trim().toLowerCase();
    final filteredProducts = query.isEmpty
        ? products
        : products.where((p) => p.name.toLowerCase().contains(query)).toList();
    final filteredCategories = query.isEmpty
        ? categories
        : categories
            .where((c) => c.name.toLowerCase().contains(query))
            .toList();

    final isEdit = widget.existing != null;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 640),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? 'Favoriyi Düzenle' : 'Yeni Favori',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // Type picker
            const Text('Tip',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _TypePill(
                    label: 'Ürün Shortcut',
                    icon: Icons.fastfood_rounded,
                    selected: _action == FavoriteAction.addProduct,
                    onTap: () => setState(() {
                      _action = FavoriteAction.addProduct;
                      _targetName = null;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TypePill(
                    label: 'Kategori Shortcut',
                    icon: Icons.category_rounded,
                    selected: _action == FavoriteAction.openCategory,
                    onTap: () => setState(() {
                      _action = FavoriteAction.openCategory;
                      _targetName = null;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Target search
            const Text('Hedef',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Ara…',
                hintStyle: const TextStyle(
                    color: AppColors.textDim, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded,
                    size: 18, color: AppColors.textDim),
                filled: true,
                fillColor: AppColors.bgInput,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Target list
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: _action == FavoriteAction.addProduct
                  ? (filteredProducts.isEmpty
                      ? const Center(
                          child: Text('Ürün bulunamadı',
                              style: TextStyle(color: AppColors.textDim)))
                      : ListView.separated(
                          itemCount: filteredProducts.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: AppColors.border),
                          itemBuilder: (_, i) {
                            final p = filteredProducts[i];
                            final sel = _targetName == p.name;
                            return ListTile(
                              dense: true,
                              selected: sel,
                              selectedTileColor: AppColors.accentDim,
                              title: Text(p.name,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textPrimary)),
                              onTap: () => setState(() {
                                _targetName = p.name;
                                if (_label.text.trim().isEmpty) {
                                  _label.text = p.name;
                                }
                              }),
                            );
                          },
                        ))
                  : (filteredCategories.isEmpty
                      ? const Center(
                          child: Text('Kategori bulunamadı',
                              style: TextStyle(color: AppColors.textDim)))
                      : ListView.separated(
                          itemCount: filteredCategories.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: AppColors.border),
                          itemBuilder: (_, i) {
                            final c = filteredCategories[i];
                            final sel = _targetName == c.name;
                            return ListTile(
                              dense: true,
                              selected: sel,
                              selectedTileColor: AppColors.accentDim,
                              title: Text(c.name,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textPrimary)),
                              onTap: () => setState(() {
                                _targetName = c.name;
                                if (_label.text.trim().isEmpty) {
                                  _label.text = c.name;
                                }
                              }),
                            );
                          },
                        )),
            ),
            const SizedBox(height: 16),

            // Label
            const Text('Buton Yazısı',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: _label,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'örn. Cola Zero',
                hintStyle: const TextStyle(
                    color: AppColors.textDim, fontSize: 14),
                filled: true,
                fillColor: AppColors.bgInput,
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Color
            const Text('Renk (opsiyonel)',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ColorSwatch(
                  color: null,
                  selected: _color == null,
                  onTap: () => setState(() => _color = null),
                ),
                for (final c in _palette)
                  _ColorSwatch(
                    color: c,
                    selected: _color?.toARGB32() == c.toARGB32(),
                    onTap: () => setState(() => _color = c),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('İptal',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _canSave() ? _save : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Kaydet',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _canSave() {
    return (_targetName ?? '').isNotEmpty && _label.text.trim().isNotEmpty;
  }

  Future<void> _save() async {
    final notifier = ref.read(favoritesProvider.notifier);
    final existing = widget.existing;
    final label = _label.text.trim();
    final target = _targetName!;

    if (existing == null) {
      await notifier.add(
        action: _action,
        target: target,
        label: label,
        color: _color,
      );
    } else {
      await notifier.update(
        existing.id,
        action: _action,
        target: target,
        label: label,
        color: _color,
        clearColor: _color == null,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentDim : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color:
                    selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color:
                    selected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color ?? AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 3 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: color == null
            ? const Text(
                'Oto',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary),
              )
            : (selected
                ? const Icon(Icons.check_rounded,
                    color: Colors.white, size: 18)
                : null),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Function Buttons section — SambaPOS-style configurable action buttons
// ---------------------------------------------------------------------------

class _FunctionButtonsSection extends ConsumerWidget {
  const _FunctionButtonsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buttonsAsync = ref.watch(actionButtonsProvider);
    final buttons =
        buttonsAsync.valueOrNull ?? const <ActionButtonEntity>[];

    return _SectionScaffold(
      title: 'Fonksiyon Butonları',
      action: ElevatedButton.icon(
        onPressed: () => _openEditor(context, ref, null),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Yeni Fonksiyon Butonu'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      children: [
        _Card(
          title: 'HAKKINDA',
          children: const [
            Text(
              'Fonksiyon butonları POS satış ekranında Schnell şeridinin '
              'altına gelir. Her buton bir işlem yapar: yüzde indirim, fix '
              'indirim, hediye, not ekle, gang değiştir, hesap yazdır. '
              'Buton adını, rengini ve işlem parametresini aşağıdan '
              'düzenleyebilirsin.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
        _Card(
          title: 'BUTONLAR (${buttons.length})',
          children: [
            if (buttons.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Henüz fonksiyon butonu yok. Yukarıdaki "Yeni Fonksiyon '
                    'Butonu" ile başla.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13),
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: buttons.length,
                itemBuilder: (ctx, i) {
                  final btn = buttons[i];
                  return _ActionButtonRow(
                    key: ValueKey(btn.id),
                    index: i,
                    button: btn,
                    onEdit: () => _openEditor(context, ref, btn),
                    onDelete: () => _confirmDelete(context, ref, btn),
                    onToggleActive: (v) => ref
                        .read(actionButtonActionsProvider.notifier)
                        .setActive(btn.id, v),
                  );
                },
                onReorder: (oldIndex, newIndex) {
                  final ordered = buttons.map((b) => b.id).toList();
                  final idx = newIndex > oldIndex ? newIndex - 1 : newIndex;
                  final moved = ordered.removeAt(oldIndex);
                  ordered.insert(idx, moved);
                  ref
                      .read(actionButtonActionsProvider.notifier)
                      .reorder(ordered);
                },
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    ActionButtonEntity? existing,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ActionButtonEditorDialog(existing: existing),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ActionButtonEntity btn,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Fonksiyon butonunu sil?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          '"${btn.label}" butonu silinecek.',
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil',
                style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(actionButtonActionsProvider.notifier).delete(btn.id);
    }
  }
}

class _ActionButtonRow extends StatelessWidget {
  const _ActionButtonRow({
    super.key,
    required this.index,
    required this.button,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  final int index;
  final ActionButtonEntity button;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleActive;

  @override
  Widget build(BuildContext context) {
    final tint = button.color ?? AppColors.primary;
    final payloadHint = _payloadHint(button);
    final positionLabel = button.position.label;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.drag_indicator_rounded,
                  size: 20, color: AppColors.textDim),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              _iconFor(button),
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  button.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: button.isActive
                        ? AppColors.textPrimary
                        : AppColors.textDim,
                    decoration: button.isActive
                        ? TextDecoration.none
                        : TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${button.actionType.label} · $positionLabel'
                  '${payloadHint.isEmpty ? '' : ' · $payloadHint'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: button.isActive,
            onChanged: onToggleActive,
            activeTrackColor: AppColors.primary,
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded,
                size: 18, color: AppColors.primary),
            onPressed: onEdit,
            tooltip: 'Düzenle',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                size: 18, color: AppColors.red),
            onPressed: onDelete,
            tooltip: 'Sil',
          ),
        ],
      ),
    );
  }

  IconData _iconFor(ActionButtonEntity b) {
    return switch (b.actionType) {
      ActionButtonType.percentDiscount => Icons.percent_rounded,
      ActionButtonType.fixedDiscount => Icons.money_off_rounded,
      ActionButtonType.markGift => Icons.card_giftcard_rounded,
      ActionButtonType.addNote => Icons.sticky_note_2_rounded,
      ActionButtonType.setCourse => Icons.restaurant_menu_rounded,
      ActionButtonType.printBill => Icons.receipt_long_rounded,
      ActionButtonType.voidItem => Icons.delete_sweep_rounded,
      ActionButtonType.customScript => Icons.code_rounded,
    };
  }

  String _payloadHint(ActionButtonEntity b) {
    switch (b.actionType) {
      case ActionButtonType.percentDiscount:
        final pct = b.actionPayload['percent'];
        return pct == null ? '' : '%$pct';
      case ActionButtonType.fixedDiscount:
        final amt = b.actionPayload['amount'];
        if (amt is int) return 'CHF ${(amt / 100).toStringAsFixed(2)}';
        return '';
      case ActionButtonType.setCourse:
        final gid = b.actionPayload['gangId'];
        return gid is String ? gid : '';
      default:
        return '';
    }
  }
}

class _ActionButtonEditorDialog extends ConsumerStatefulWidget {
  const _ActionButtonEditorDialog({this.existing});

  final ActionButtonEntity? existing;

  @override
  ConsumerState<_ActionButtonEditorDialog> createState() =>
      _ActionButtonEditorDialogState();
}

class _ActionButtonEditorDialogState
    extends ConsumerState<_ActionButtonEditorDialog> {
  late TextEditingController _label;
  late ActionButtonPosition _position;
  late ActionButtonType _actionType;
  Color? _color;
  String? _iconName;

  // Payload fields — only the ones the selected action uses are active.
  int _percent = 10;
  int _amountCents = 500;
  String? _gangId;

  /// Roles allowed to see this button. Empty = visible to every role
  /// (the historical default before role gating was wired up).
  late Set<UserRole> _allowedRoles;

  static const List<Color> _palette = [
    Color(0xFFE53935),
    Color(0xFFF57C00),
    Color(0xFFFBC02D),
    Color(0xFF66BB6A),
    Color(0xFF2E7D32),
    Color(0xFF26A69A),
    Color(0xFF29B6F6),
    Color(0xFF3841E9),
    Color(0xFFBF5AF2),
    Color(0xFFE91E63),
  ];

  static const List<_IconOption> _icons = [
    _IconOption('percent', Icons.percent_rounded),
    _IconOption('card_giftcard', Icons.card_giftcard_rounded),
    _IconOption('sticky_note_2', Icons.sticky_note_2_rounded),
    _IconOption('receipt_long', Icons.receipt_long_rounded),
    _IconOption('restaurant_menu', Icons.restaurant_menu_rounded),
    _IconOption('money_off', Icons.money_off_rounded),
    _IconOption('local_offer', Icons.local_offer_rounded),
    _IconOption('delete_sweep', Icons.delete_sweep_rounded),
    _IconOption('star', Icons.star_rounded),
    _IconOption('bolt', Icons.bolt_rounded),
  ];

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _label = TextEditingController(text: ex?.label ?? '');
    _position = ex?.position ?? ActionButtonPosition.ticketScreen;
    _actionType = ex?.actionType ?? ActionButtonType.percentDiscount;
    _color = ex?.color;
    _iconName = ex?.iconName;
    final payload = ex?.actionPayload ?? const <String, dynamic>{};
    final pct = payload['percent'];
    if (pct is int) _percent = pct;
    final amt = payload['amount'];
    if (amt is int) _amountCents = amt;
    final gid = payload['gangId'];
    if (gid is String) _gangId = gid;

    // Seed role filter from the stored list. Unknown / legacy names are
    // dropped silently so a stale seed from a future build can't crash
    // the editor when that role enum value doesn't exist here yet.
    final stored = ex?.roleFilter ?? const <String>[];
    _allowedRoles = {
      for (final name in stored)
        for (final r in UserRole.values)
          if (r.name == name) r,
    };
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        isEdit ? 'Fonksiyon butonunu düzenle' : 'Yeni fonksiyon butonu',
        style: const TextStyle(color: AppColors.textPrimary),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FieldLabel('Etiket'),
              TextField(
                controller: _label,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'ör. %10 Rabatt',
                  hintStyle: TextStyle(color: AppColors.textDim),
                ),
              ),
              const SizedBox(height: 16),
              _FieldLabel('İşlem'),
              DropdownButtonFormField<ActionButtonType>(
                initialValue: _actionType,
                isExpanded: true,
                items: [
                  for (final t in ActionButtonType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _actionType = v);
                },
              ),
              const SizedBox(height: 16),
              _FieldLabel('Konum'),
              DropdownButtonFormField<ActionButtonPosition>(
                initialValue: _position,
                isExpanded: true,
                items: [
                  for (final p in ActionButtonPosition.values)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _position = v);
                },
              ),
              const SizedBox(height: 16),
              ..._payloadFields(),
              const SizedBox(height: 16),
              _FieldLabel('Renk'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ColorSwatch(
                    color: null,
                    selected: _color == null,
                    onTap: () => setState(() => _color = null),
                  ),
                  for (final c in _palette)
                    _ColorSwatch(
                      color: c,
                      selected: _color?.toARGB32() == c.toARGB32(),
                      onTap: () => setState(() => _color = c),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _FieldLabel('İkon (opsiyonel)'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _IconSwatch(
                    icon: null,
                    selected: _iconName == null,
                    onTap: () => setState(() => _iconName = null),
                  ),
                  for (final opt in _icons)
                    _IconSwatch(
                      icon: opt.icon,
                      selected: _iconName == opt.name,
                      onTap: () => setState(() => _iconName = opt.name),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _FieldLabel('Görünürlük (rol filtresi)'),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'Hiçbirini seçmezsen buton herkese görünür. Bir veya '
                  'birkaç rol seçersen buton sadece o rollerde oturum '
                  'açan kullanıcılara gösterilir. Admin rolü her butonu '
                  'daima görür.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textDim,
                    height: 1.4,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final role in UserRole.values)
                    FilterChip(
                      label: Text(_labelForRole(role)),
                      selected: _allowedRoles.contains(role),
                      onSelected: (sel) {
                        setState(() {
                          if (sel) {
                            _allowedRoles.add(role);
                          } else {
                            _allowedRoles.remove(role);
                          }
                        });
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }

  List<Widget> _payloadFields() {
    switch (_actionType) {
      case ActionButtonType.percentDiscount:
        return [
          _FieldLabel('Yüzde (%)'),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _percent.toDouble().clamp(1, 100),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: '%$_percent',
                  onChanged: (v) => setState(() => _percent = v.round()),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text('%$_percent',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ];
      case ActionButtonType.fixedDiscount:
        return [
          _FieldLabel('Tutar (CHF)'),
          TextFormField(
            initialValue: (_amountCents / 100).toStringAsFixed(2),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppColors.textPrimary),
            onChanged: (s) {
              final v = double.tryParse(s.replaceAll(',', '.'));
              if (v == null) return;
              setState(() => _amountCents = (v * 100).round());
            },
          ),
        ];
      case ActionButtonType.setCourse:
        final gangs =
            ref.watch(gangTemplatesProvider).valueOrNull ?? const [];
        return [
          _FieldLabel('Gang'),
          DropdownButtonFormField<String>(
            initialValue: gangs.any((g) => g.id == _gangId) ? _gangId : null,
            isExpanded: true,
            items: [
              for (final g in gangs)
                DropdownMenuItem<String>(
                  value: g.id,
                  child: Text('${g.sortOrder}. ${g.name}'),
                ),
            ],
            onChanged: (v) => setState(() => _gangId = v),
          ),
          if (gangs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Önce ayarlardan gang tanımla.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ),
        ];
      case ActionButtonType.markGift:
      case ActionButtonType.addNote:
      case ActionButtonType.printBill:
      case ActionButtonType.voidItem:
      case ActionButtonType.customScript:
        return const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Bu işlem ek parametre almaz.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
        ];
    }
  }

  Map<String, dynamic> _buildPayload() {
    switch (_actionType) {
      case ActionButtonType.percentDiscount:
        return {'percent': _percent};
      case ActionButtonType.fixedDiscount:
        return {'amount': _amountCents, 'currency': 'CHF'};
      case ActionButtonType.setCourse:
        return _gangId == null ? <String, dynamic>{} : {'gangId': _gangId};
      case ActionButtonType.markGift:
      case ActionButtonType.addNote:
      case ActionButtonType.printBill:
      case ActionButtonType.voidItem:
      case ActionButtonType.customScript:
        return <String, dynamic>{};
    }
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Etiket boş olamaz')),
      );
      return;
    }
    final payload = _buildPayload();
    final notifier = ref.read(actionButtonActionsProvider.notifier);
    final navigator = Navigator.of(context);
    final ex = widget.existing;

    // An empty selection serialises as null (historical "visible to all"
    // sentinel); a non-empty set is persisted as a sorted list of role
    // names so two buttons with the same filter serialize identically.
    final rolesList = _allowedRoles.isEmpty
        ? null
        : (_allowedRoles.map((r) => r.name).toList()..sort());

    bool ok;
    if (ex == null) {
      ok = await notifier.create(
        label: label,
        position: _position,
        actionType: _actionType,
        actionPayload: payload,
        colorValue: _color?.toARGB32(),
        iconName: _iconName,
        roleFilter: rolesList,
      );
    } else {
      ok = await notifier.update(
        ex.copyWith(
          label: label,
          position: _position,
          actionType: _actionType,
          actionPayload: payload,
          colorValue: _color?.toARGB32(),
          clearColor: _color == null,
          iconName: _iconName,
          clearIcon: _iconName == null,
          roleFilter: rolesList,
          clearRoleFilter: rolesList == null,
        ),
      );
    }
    if (!ok) return;
    if (mounted) navigator.pop();
  }

  String _labelForRole(UserRole role) => switch (role) {
        UserRole.admin => 'Admin',
        UserRole.manager => 'Müdür',
        UserRole.waiter => 'Garson',
        UserRole.cashier => 'Kasiyer',
        UserRole.kitchen => 'Mutfak',
      };
}

class _IconOption {
  const _IconOption(this.name, this.icon);
  final String name;
  final IconData icon;
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _IconSwatch extends StatelessWidget {
  const _IconSwatch({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: icon == null
            ? const Icon(Icons.not_interested_rounded,
                size: 16, color: AppColors.textDim)
            : Icon(icon, size: 18, color: AppColors.textPrimary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Theme colours section — operator-picked light/dark accent + surface
// ---------------------------------------------------------------------------

const List<Color> _kThemePresetPrimaries = <Color>[
  Color(0xFF3841E9), // Kinetic default (matches GcColors.primary)
  Color(0xFF486BE1), // POS v2 selection blue
  Color(0xFF2BAE66), // Pay green
  Color(0xFFD3543E), // Haupt red
  Color(0xFFD88B3C), // Pasta orange
  Color(0xFFC4539A), // Dessert magenta
  Color(0xFF467DCB), // Drink azure
  Color(0xFF5E35B1), // Deep purple
  Color(0xFF00838F), // Teal 800
  Color(0xFF2B2E38), // Graphite ink
];

const List<Color> _kThemePresetLightSurfaces = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFFF4F5F7),
  Color(0xFFFDF6EC),
  Color(0xFFECEFF4),
  Color(0xFFFFF8F0),
  Color(0xFFF0F7F4),
];

const List<Color> _kThemePresetDarkSurfaces = <Color>[
  Color(0xFF0E1116),
  Color(0xFF161A21),
  Color(0xFF10141B),
  Color(0xFF1A1320),
  Color(0xFF121826),
  Color(0xFF0D1410),
];

String _colorToHex(Color c) {
  final rgb = c.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class _ThemeColorsSection extends ConsumerWidget {
  const _ThemeColorsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(themeCustomizationProvider);
    final custom = async.valueOrNull ?? const ThemeCustomization();
    final notifier = ref.read(themeCustomizationProvider.notifier);

    return _SectionScaffold(
      title: 'Tema Renkleri',
      action: custom.isDefault
          ? null
          : OutlinedButton.icon(
              onPressed: () async {
                await notifier.restoreDefaults();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Varsayılan renklere dönüldü'),
                      duration: Duration(milliseconds: 1500),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Varsayılana Dön'),
            ),
      children: [
        const _Card(
          title: 'HAKKINDA',
          children: [
            Text(
              'Vurgu rengi butonlar, seçili durumlar ve form odaklarında '
              'kullanılır. Yüzey rengi uygulamanın arka planını etkiler. '
              'Değişiklikler anında uygulanır.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
        _Card(
          title: 'VURGU RENGI — AÇIK MOD',
          children: [
            _ColorPickerRow(
              selectedHex: custom.lightPrimaryHex,
              presets: _kThemePresetPrimaries,
              onPick: notifier.setLightPrimary,
            ),
          ],
        ),
        _Card(
          title: 'VURGU RENGI — KARANLIK MOD',
          children: [
            _ColorPickerRow(
              selectedHex: custom.darkPrimaryHex,
              presets: _kThemePresetPrimaries,
              onPick: notifier.setDarkPrimary,
            ),
          ],
        ),
        _Card(
          title: 'YUZEY — AÇIK MOD',
          children: [
            _ColorPickerRow(
              selectedHex: custom.lightSurfaceHex,
              presets: _kThemePresetLightSurfaces,
              onPick: notifier.setLightSurface,
            ),
          ],
        ),
        _Card(
          title: 'YUZEY — KARANLIK MOD',
          children: [
            _ColorPickerRow(
              selectedHex: custom.darkSurfaceHex,
              presets: _kThemePresetDarkSurfaces,
              onPick: notifier.setDarkSurface,
            ),
          ],
        ),
      ],
    );
  }
}

class _ColorPickerRow extends StatefulWidget {
  const _ColorPickerRow({
    required this.selectedHex,
    required this.presets,
    required this.onPick,
  });

  final String? selectedHex;
  final List<Color> presets;
  final ValueChanged<String?> onPick;

  @override
  State<_ColorPickerRow> createState() => _ColorPickerRowState();
}

class _ColorPickerRowState extends State<_ColorPickerRow> {
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(text: widget.selectedHex ?? '');
  }

  @override
  void didUpdateWidget(_ColorPickerRow old) {
    super.didUpdateWidget(old);
    if (old.selectedHex != widget.selectedHex) {
      _hexController.text = widget.selectedHex ?? '';
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = v2ParseHex(widget.selectedHex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ColorSwatch(
              color: null,
              selected: widget.selectedHex == null,
              onTap: () => widget.onPick(null),
            ),
            for (final c in widget.presets)
              _ColorSwatch(
                color: c,
                selected: selected != null &&
                    (c.toARGB32() & 0x00FFFFFF) ==
                        (selected.toARGB32() & 0x00FFFFFF),
                onTap: () => widget.onPick(_colorToHex(c)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _hexController,
                decoration: const InputDecoration(
                  labelText: 'Özel HEX (#RRGGBB)',
                  hintText: '#3841E9',
                  prefixIcon: Icon(Icons.tag_rounded, size: 18),
                ),
                onSubmitted: (value) {
                  final trimmed = value.trim();
                  if (trimmed.isEmpty) {
                    widget.onPick(null);
                    return;
                  }
                  final parsed = v2ParseHex(trimmed);
                  if (parsed == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Geçersiz HEX. Örnek: #3841E9'),
                        duration: Duration(milliseconds: 1500),
                      ),
                    );
                    return;
                  }
                  widget.onPick(_colorToHex(parsed));
                },
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () {
                final parsed = v2ParseHex(_hexController.text.trim());
                if (parsed == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Geçersiz HEX. Örnek: #3841E9'),
                      duration: Duration(milliseconds: 1500),
                    ),
                  );
                  return;
                }
                widget.onPick(_colorToHex(parsed));
              },
              child: const Text('Uygula'),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Loyalty section — configurable earn rate / redemption / tier thresholds
// ---------------------------------------------------------------------------

class _LoyaltySection extends ConsumerStatefulWidget {
  const _LoyaltySection();

  @override
  ConsumerState<_LoyaltySection> createState() => _LoyaltySectionState();
}

class _LoyaltySectionState extends ConsumerState<_LoyaltySection> {
  /// Snapshot of the currently-persisted settings. We keep a local mutable
  /// copy so the form stays editable while the user is typing; the provider
  /// is only touched on "Kaydet".
  LoyaltySettings? _draft;
  late final TextEditingController _earnCtrl;
  late final TextEditingController _redeemCtrl;
  late final TextEditingController _silverCtrl;
  late final TextEditingController _goldCtrl;

  @override
  void initState() {
    super.initState();
    _earnCtrl = TextEditingController();
    _redeemCtrl = TextEditingController();
    _silverCtrl = TextEditingController();
    _goldCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _earnCtrl.dispose();
    _redeemCtrl.dispose();
    _silverCtrl.dispose();
    _goldCtrl.dispose();
    super.dispose();
  }

  void _seed(LoyaltySettings s) {
    _draft = s;
    _earnCtrl.text = s.pointsPerChfSpent.toString();
    _redeemCtrl.text = s.centsPerPoint.toString();
    _silverCtrl.text = (s.silverThresholdCents ~/ 100).toString();
    _goldCtrl.text = (s.goldThresholdCents ~/ 100).toString();
  }

  LoyaltySettings _readForm(LoyaltySettings base) {
    final earn = int.tryParse(_earnCtrl.text) ?? base.pointsPerChfSpent;
    final redeem = int.tryParse(_redeemCtrl.text) ?? base.centsPerPoint;
    final silverChf = int.tryParse(_silverCtrl.text);
    final goldChf = int.tryParse(_goldCtrl.text);
    return base.copyWith(
      pointsPerChfSpent: earn,
      centsPerPoint: redeem,
      silverThresholdCents:
          silverChf != null ? silverChf * 100 : base.silverThresholdCents,
      goldThresholdCents:
          goldChf != null ? goldChf * 100 : base.goldThresholdCents,
    );
  }

  Future<void> _save() async {
    final current = _draft ?? const LoyaltySettings();
    final next = _readForm(current);
    if (!next.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Geçersiz değerler. Tüm sayılar pozitif ve Gold > Silber olmalı.',
          ),
          duration: Duration(milliseconds: 2200),
        ),
      );
      return;
    }
    await ref.read(loyaltySettingsProvider.notifier).save(next);
    if (!mounted) return;
    setState(() => _draft = next);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Treueprogramm kaydedildi'),
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  Future<void> _reset() async {
    await ref.read(loyaltySettingsProvider.notifier).resetToDefaults();
    if (!mounted) return;
    setState(() => _seed(const LoyaltySettings()));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(loyaltySettingsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('$e', style: const TextStyle(color: AppColors.red)),
      ),
      data: (settings) {
        // (Re)seed the controllers when the provider emits a new value
        // that differs from our current draft — e.g. first load or reset.
        if (_draft != settings) {
          _seed(settings);
        }
        final live = _readForm(settings);
        final sampleSpent = 10000; // CHF 100
        final samplePoints = (sampleSpent ~/ 100) * live.pointsPerChfSpent;
        final sampleDiscount = samplePoints * live.centsPerPoint;
        return _SectionScaffold(
          title: 'Treueprogramm',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('Standart'),
                onPressed: _reset,
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Kaydet'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _save,
              ),
            ],
          ),
          children: [
            _Card(
              title: 'DURUM',
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Programı etkinleştir',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    settings.isActive
                        ? 'Müşteriler puan biriktirebilir ve eritebilir'
                        : 'Puan kazanımı/eritimi geçici olarak devre dışı',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  value: settings.isActive,
                  onChanged: (v) => ref
                      .read(loyaltySettingsProvider.notifier)
                      .update((s) => s.copyWith(isActive: v)),
                ),
              ],
            ),
            _Card(
              title: 'KAZANIM (EARN RATE)',
              children: [
                const Text(
                  'Her 1 CHF harcandığında kaç puan verilecek.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('1 CHF =',
                        style: TextStyle(color: AppColors.textPrimary)),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _earnCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _fieldDecoration(),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Punkt(e)',
                        style: TextStyle(color: AppColors.textPrimary)),
                  ],
                ),
              ],
            ),
            _Card(
              title: 'ERITIM (REDEMPTION)',
              children: [
                const Text(
                  'Her 1 puan kaç santim (cent) indirim açığa çıkarır.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('1 Punkt =',
                        style: TextStyle(color: AppColors.textPrimary)),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _redeemCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _fieldDecoration(),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Rp. (santim)',
                        style: TextStyle(color: AppColors.textPrimary)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Örnek: $samplePoints Punkt = '
                  'CHF ${(sampleDiscount / 100).toStringAsFixed(2)} indirim',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDim,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            _Card(
              title: 'TIER EŞİKLERİ (CHF)',
              children: [
                const Text(
                  'Müşteri yaşam boyu ciroya göre Bronz / Silber / Gold '
                  'kademelerine yükselir. Eşikler CHF cinsindendir.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(width: 80,
                        child: Text('Silber',
                            style: TextStyle(
                                color: Color(0xFFC0C0C0),
                                fontWeight: FontWeight.w700))),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _silverCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _fieldDecoration(suffix: 'CHF'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(width: 80,
                        child: Text('Gold',
                            style: TextStyle(
                                color: AppColors.yellow,
                                fontWeight: FontWeight.w700))),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _goldCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _fieldDecoration(suffix: 'CHF'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            _Card(
              title: 'ÖNIZLEME',
              children: [
                Text(
                  '• 1 CHF = ${live.pointsPerChfSpent} Punkt(e)',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '• ${live.centsPerPoint == 1 ? "100 Punkte = CHF 1.00" : "1 Punkt = ${live.centsPerPoint} Rp."} indirim',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '• Silber: ab CHF ${(live.silverThresholdCents / 100).toStringAsFixed(0)} Umsatz',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
                Text(
                  '• Gold: ab CHF ${(live.goldThresholdCents / 100).toStringAsFixed(0)} Umsatz',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  InputDecoration _fieldDecoration({String? suffix}) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.bgInput,
        suffixText: suffix,
        suffixStyle: const TextStyle(color: AppColors.textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      );
}

// ---------------------------------------------------------------------------
// Updates section — manifest-based OTA check
// ---------------------------------------------------------------------------

class _UpdatesSection extends ConsumerStatefulWidget {
  const _UpdatesSection();

  @override
  ConsumerState<_UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends ConsumerState<_UpdatesSection> {
  late final TextEditingController _urlController;
  bool _dirty = false;
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _syncFromState(UpdateChannelSettings settings) {
    if (_bootstrapped) return;
    _urlController.text = settings.manifestUrl;
    _bootstrapped = true;
  }

  Future<void> _save(UpdateChannelSettings current) async {
    await ref.read(updateChannelSettingsProvider.notifier).save(
          current.copyWith(manifestUrl: _urlController.text.trim()),
        );
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Güncelleme kanalı kaydedildi.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _check() async {
    final manifest =
        await ref.read(updateCheckControllerProvider.notifier).checkNow();
    if (!mounted) return;
    final state = ref.read(updateCheckControllerProvider);
    if (state.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.errorMessage!),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (manifest == null) return;
    final msg = manifest.isNewerThan(appBuildNumber)
        ? 'Yeni sürüm bulundu: ${manifest.versionName} (build ${manifest.buildNumber}).'
        : 'Uygulama güncel. Son sürüm: ${manifest.versionName}.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _download() async {
    final ok =
        await ref.read(updateCheckControllerProvider.notifier).openDownload();
    if (!mounted || ok) return;
    final state = ref.read(updateCheckControllerProvider);
    if (state.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.errorMessage!),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncChannel = ref.watch(updateChannelSettingsProvider);
    final checkState = ref.watch(updateCheckControllerProvider);

    final settings =
        asyncChannel.valueOrNull ?? const UpdateChannelSettings();
    _syncFromState(settings);

    return _SectionScaffold(
      title: 'Güncelleme',
      children: [
        _Card(
          title: 'GEÇERLİ SÜRÜM',
          children: [
            _AboutRow(
              label: 'Uygulama',
              value: 'GastroCore POS',
            ),
            _AboutRow(
              label: 'Sürüm',
              value: '$appVersionName (build $appBuildNumber)',
            ),
            _AboutRow(
              label: 'Kanal',
              value: settings.channel.label,
            ),
          ],
        ),
        _Card(
          title: 'MANİFEST URL',
          children: [
            const Text(
              'Güncelleme kontrolü için manifest JSON URL\'i. Boş bırakılırsa kontrol çalışmaz.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'https://...',
                isDense: true,
                filled: true,
                fillColor: AppColors.bgInput,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() => _dirty = true),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                DropdownButton<UpdateChannel>(
                  value: settings.channel,
                  onChanged: (value) {
                    if (value == null) return;
                    ref
                        .read(updateChannelSettingsProvider.notifier)
                        .update((s) => s.copyWith(channel: value));
                  },
                  items: UpdateChannel.values
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.label),
                        ),
                      )
                      .toList(),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _dirty ? () => _save(settings) : null,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Kaydet'),
                ),
              ],
            ),
          ],
        ),
        _Card(
          title: 'GÜNCELLEME KONTROLÜ',
          children: [
            Row(
              children: [
                FilledButton.icon(
                  onPressed: checkState.isChecking ? null : _check,
                  icon: checkState.isChecking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    checkState.isChecking
                        ? 'Kontrol ediliyor...'
                        : 'Güncellemeleri kontrol et',
                  ),
                ),
                const SizedBox(width: 12),
                if (checkState.checkedAt != null)
                  Text(
                    'Son: ${DateFormat('dd.MM.yyyy HH:mm').format(checkState.checkedAt!.toLocal())}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
            if (checkState.manifest != null) ...[
              const SizedBox(height: 16),
              _UpdateAvailableCard(
                manifest: checkState.manifest!,
                onDownload: _download,
              ),
            ] else if (checkState.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                checkState.errorMessage!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.error,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _UpdateAvailableCard extends StatelessWidget {
  const _UpdateAvailableCard({
    required this.manifest,
    required this.onDownload,
  });

  final UpdateManifest manifest;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final newer = manifest.isNewerThan(appBuildNumber);
    final mandatory = manifest.isMandatoryFor(appBuildNumber);
    final accent = mandatory
        ? AppColors.error
        : (newer ? AppColors.primary : AppColors.textSecondary);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                mandatory
                    ? Icons.warning_amber_rounded
                    : newer
                        ? Icons.system_update_alt_rounded
                        : Icons.check_circle_rounded,
                color: accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                mandatory
                    ? 'Zorunlu güncelleme'
                    : newer
                        ? 'Yeni sürüm mevcut'
                        : 'Uygulama güncel',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sürüm: ${manifest.versionName} (build ${manifest.buildNumber})',
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
          if (manifest.changelog.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              manifest.changelog,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
          if (manifest.sha256 != null && manifest.sha256!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'SHA256: ${manifest.sha256}',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          if (newer)
            FilledButton.icon(
              onPressed: onDownload,
              style: FilledButton.styleFrom(backgroundColor: accent),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('İndir'),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sync dead-letter queue (DLQ) section
// ---------------------------------------------------------------------------

class _SyncDlqSection extends ConsumerWidget {
  const _SyncDlqSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(deadLetterEventsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Senkronizasyon — Ölü Mesaj Kuyruğu',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Yeniden deneme limiti dolmuş ve otomatik sıradan çıkarılmış '
            'olay kayıtları. Her birini yeniden kuyruğa alabilir veya '
            'kalıcı olarak silebilirsiniz.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: eventsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('DLQ okunamadı: $e'),
              ),
              data: (events) {
                if (events.isEmpty) {
                  return const Center(
                    child: Text(
                      'DLQ boş. Tüm olaylar normal kuyruktan geçiyor.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) => _DlqTile(event: events[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DlqTile extends ConsumerWidget {
  const _DlqTile({required this.event});

  final SyncEventEntity event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final createdAt = DateFormat('dd.MM.yyyy HH:mm').format(event.createdAt);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${event.tableName} · ${event.operation.name}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Kayıt: ${event.recordId}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Oluşturuldu: $createdAt · Deneme: ${event.retryCount}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (event.errorMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Hata: ${event.errorMessage}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await ref
                      .read(syncRepositoryProvider)
                      .requeueDeadLetterEvent(event.id);
                  ref.invalidate(deadLetterEventsProvider);
                  ref.invalidate(deadLetterCountProvider);
                },
                icon: const Icon(Icons.replay_rounded, size: 16),
                label: const Text('Tekrar Dene'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  await ref
                      .read(syncRepositoryProvider)
                      .purgeDeadLetterEvent(event.id);
                  ref.invalidate(deadLetterEventsProvider);
                  ref.invalidate(deadLetterCountProvider);
                },
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Sil'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// M7 — POS product tile size selector
// ---------------------------------------------------------------------------

/// Composite control surfaced inside the WORKFLOW card on the Restaurant
/// settings tab. Four pieces, all bound to the same `posTileScale`
/// scalar plus the `posTileMode` enum:
///
///   * **AutoFit switch** — when on, the items grid in the sales shell
///     packs the active category to fill the viewport (no scroll). The
///     manual scale + presets are then irrelevant, so we grey them out.
///   * **XS/S/M/L/XL preset shortcuts** — quick taps that snap the
///     scalar to one of the canonical [PosTileSize] presets (0.7 /
///     0.85 / 1.0 / 1.2 / 1.5). Disabled when AutoFit is on.
///   * **Free-form slider** — 0.7 .. 1.5 in 0.05 steps. Drives the
///     scalar directly so operators can dial in a value that doesn't
///     match any preset. Disabled when AutoFit is on.
///   * **Live preview tile** — a miniature `_PCard`-shaped card that
///     renders product name + price using the current scale. Greyed
///     out (faded) when AutoFit is on so the operator sees the manual
///     control set is currently bypassed.
class _PosTileSizeControls extends StatelessWidget {
  const _PosTileSizeControls({
    required this.scale,
    required this.mode,
    required this.onScaleChanged,
    required this.onModeChanged,
  });

  /// Current `posTileScale` value, already clamped to `[0.7, 1.5]` by
  /// the caller.
  final double scale;

  /// Current layout strategy. When [PosTileMode.autoFit] the manual
  /// controls (segmented + slider + preview) render disabled.
  final PosTileMode mode;

  /// Setter wired to `restaurantSettingsProvider.update((s) =>
  /// s.copyWith(posTileScale: next))`. Receives a raw double so the
  /// slider can hand off any 0.05 step in range; the segmented preset
  /// shortcut hands off canonical scales (0.7 / 0.85 / 1.0 / 1.2 / 1.5).
  final ValueChanged<double> onScaleChanged;

  /// Setter wired to `restaurantSettingsProvider.update((s) =>
  /// s.copyWith(posTileMode: next))`. Driven by the AutoFit switch.
  final ValueChanged<PosTileMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nearestPreset = PosTileSize.forScale(scale);
    final autoFitOn = mode == PosTileMode.autoFit;
    // Manual controls are bypassed while autoFit owns the layout —
    // greyed-out look mirrors Material disabled affordances.
    final disabled = autoFitOn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // AutoFit switch. Sits at the top so the operator sees it before
        // touching the manual controls below.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.posTileAutoFitLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.posTileAutoFitDesc,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              key: const Key('tile-mode-autofit'),
              value: autoFitOn,
              onChanged: (v) => onModeChanged(
                v ? PosTileMode.autoFit : PosTileMode.fixed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Preset shortcuts (XS/S/M/L/XL). Stay live alongside the slider
        // so a tap snaps the scalar back onto a canonical value. When
        // autoFit is on, every button renders disabled (grey).
        IgnorePointer(
          ignoring: disabled,
          child: Opacity(
            opacity: disabled ? 0.45 : 1.0,
            child: _PosTileSizeSegmented(
              value: nearestPreset,
              l10n: l10n,
              onChanged: (size) => onScaleChanged(size.scale),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Free-form slider. divisions:16 → 0.05 step over [0.7, 1.5].
        Opacity(
          opacity: disabled ? 0.45 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'Slider',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${scale.toStringAsFixed(2)}x',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              Slider(
                min: 0.7,
                max: 1.5,
                divisions: 16,
                value: scale.clamp(0.7, 1.5),
                label: scale.toStringAsFixed(2),
                onChanged: disabled
                    ? null
                    : (v) {
                        // Snap to two decimals so the persisted scalar
                        // tracks the slider's 0.05 step exactly. Avoids
                        // 1.0500000000001 cruft.
                        final snapped = (v * 20).round() / 20.0;
                        onScaleChanged(snapped);
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Live preview demo tile — same colour palette and typography
        // shape as `_PCard` on the sales shell so the operator gets a
        // realistic before/after as they drag the slider. Faded when
        // AutoFit is on (control set bypassed).
        const Text(
          'Vorschau',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Opacity(
            opacity: disabled ? 0.45 : 1.0,
            child: _PosTileDemo(scale: scale),
          ),
        ),
      ],
    );
  }
}

/// Miniature replica of the sales-shell `_PCard` used on the settings
/// screen's tile-size preview. Only mirrors the layout and typography
/// scaling — no taps, no riverpod, no cart badge — so this widget can
/// live in the settings file without dragging the v2 shell internals
/// across module boundaries.
class _PosTileDemo extends StatelessWidget {
  const _PosTileDemo({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    // Matches the canonical 180dp min tile width × 130dp row height
    // from `_ItemsGrid`, scaled identically.
    final width = 180.0 * scale;
    final height = 130.0 * scale;
    // Sample palette mirroring v2 category tints (warm orange) so the
    // preview reads as a real product tile, not a generic card.
    const bg = Color(0xFFE6884A);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Centred product name — mirrors the new `_PCard` layout.
          Expanded(
            child: Center(
              child: Text(
                'Demo Ürün',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Price row, also centred to match the production tile.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'CHF',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11 * scale,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '12.50',
                style: TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 18 * scale,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Five-button segmented control surfaced inside the WORKFLOW card on
/// the Restaurant settings tab. Picks one of [PosTileSize.xs] / `s` /
/// `m` / `l` / `xl`; the selected preset's `scale` factor flows
/// through `RestaurantSettings.posTileScale` to every product tile in
/// the pilot v2 sales shell (Schnellverkauf bar + items grid).
class _PosTileSizeSegmented extends StatelessWidget {
  const _PosTileSizeSegmented({
    required this.value,
    required this.l10n,
    required this.onChanged,
  });

  final PosTileSize value;
  final AppLocalizations l10n;
  final ValueChanged<PosTileSize> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          for (final size in PosTileSize.values)
            Expanded(
              child: _PosTileSizeButton(
                key: Key('tile-size-${size.name}'),
                label: switch (size) {
                  PosTileSize.xs => l10n.posTileSizeXs,
                  PosTileSize.s => l10n.posTileSizeS,
                  PosTileSize.m => l10n.posTileSizeM,
                  PosTileSize.l => l10n.posTileSizeL,
                  PosTileSize.xl => l10n.posTileSizeXl,
                },
                hint: '${size.scale}x',
                isActive: size == value,
                onTap: () => onChanged(size),
              ),
            ),
        ],
      ),
    );
  }
}

class _PosTileSizeButton extends StatelessWidget {
  const _PosTileSizeButton({
    super.key,
    required this.label,
    required this.hint,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? Colors.white
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 10,
                  color: isActive
                      ? Colors.white.withValues(alpha: 0.85)
                      : AppColors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PosModeSection — Fast Sale / Hybrid (Tisch + Schnell) toggle.
// ---------------------------------------------------------------------------

class _PosModeSection extends ConsumerWidget {
  const _PosModeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final effective = ref.watch(effectiveRestaurantConfigProvider);
    final selected = effective.posMode;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsPosMode,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          _PosModeRadio(
            value: PosMode.fastSale,
            groupValue: selected,
            title: l10n.settingsPosModeFastSale,
            subtitle: l10n.settingsPosModeFastSaleDesc,
            onChanged: (v) => _setMode(ref, v, effective.featureTisch),
          ),
          const SizedBox(height: 12),
          _PosModeRadio(
            value: PosMode.hybrid,
            groupValue: selected,
            title: l10n.settingsPosModeHybrid,
            subtitle: l10n.settingsPosModeHybridDesc,
            // Hybrid implies feature_tisch is on for this device.
            onChanged: (v) => _setMode(ref, v, true),
          ),
        ],
      ),
    );
  }

  Future<void> _setMode(WidgetRef ref, PosMode mode, bool featureTisch) async {
    await ref.read(restaurantConfigOverrideProvider.notifier).setOverride(
          RestaurantConfig(
            posMode: mode,
            featureTisch: mode == PosMode.hybrid ? true : featureTisch,
          ),
        );
  }
}

class _PosModeRadio extends StatelessWidget {
  const _PosModeRadio({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final PosMode value;
  final PosMode groupValue;
  final String title;
  final String subtitle;
  final ValueChanged<PosMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
          border: Border.all(
            color: isSelected
                ? const Color(0xFF1D4ED8)
                : const Color(0xFFE5E7EB),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Radio<PosMode>(
              value: value,
              groupValue: groupValue,
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
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
