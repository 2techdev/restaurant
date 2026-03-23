/// Minimal settings screen for the Order Display Screen.
///
/// Accessible via long-press on the settings icon in [OdsMainScreen].
/// Covers:
///   - Restaurant name
///   - Display language
///   - Sound on/off
///   - Auto-remove timeout
///   - Sync server URL
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/features/ods/presentation/providers/ods_provider.dart';
import 'package:gastrocore_pos/features/ods/theme/ods_theme.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';

class OdsSettingsScreen extends ConsumerStatefulWidget {
  const OdsSettingsScreen({super.key});

  @override
  ConsumerState<OdsSettingsScreen> createState() => _OdsSettingsScreenState();
}

class _OdsSettingsScreenState extends ConsumerState<OdsSettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _syncUrlController;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: ref.read(odsRestaurantNameProvider));
    _syncUrlController =
        TextEditingController(text: ref.read(syncServerUrlProvider));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _syncUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final persistence = ref.read(odsSettingsPersistenceProvider);

    await persistence.saveRestaurantName(_nameController.text.trim());

    final syncUrl = _syncUrlController.text.trim();
    if (syncUrl.isNotEmpty) {
      ref.read(syncServerUrlProvider.notifier).state = syncUrl;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sync_server_url', syncUrl);
    }

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final soundEnabled = ref.watch(odsSoundEnabledProvider);
    final autoRemoveMinutes = ref.watch(odsAutoRemoveMinutesProvider);
    final persistence = ref.read(odsSettingsPersistenceProvider);

    return Scaffold(
      backgroundColor: OdsColors.bgPage,
      appBar: AppBar(
        backgroundColor: OdsColors.bgHeader,
        title: const Text(
          'Display Settings',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: OdsColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: OdsColors.textSecondary),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'DONE',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: OdsColors.ready,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        children: [
          // ── Restaurant ──────────────────────────────────────────────────
          _SectionHeader(title: 'RESTAURANT'),
          _SettingsCard(
            child: _TextRow(
              label: 'Restaurant Name',
              controller: _nameController,
              hint: 'e.g. Bella Italia',
            ),
          ),

          const SizedBox(height: 24),

          // ── Display ─────────────────────────────────────────────────────
          _SectionHeader(title: 'DISPLAY'),
          _SettingsCard(
            child: Column(
              children: [
                // Sound toggle
                _SwitchRow(
                  label: 'Sound Chime',
                  subtitle: 'Play a chime when orders are ready',
                  value: soundEnabled,
                  onChanged: persistence.saveSoundEnabled,
                ),
                const _Divider(),
                // Auto-remove slider
                _SliderRow(
                  label: 'Auto-Remove After',
                  value: autoRemoveMinutes.toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  format: (v) => '${v.round()} min',
                  onChanged: (v) =>
                      persistence.saveAutoRemoveMinutes(v.round()),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Connectivity ─────────────────────────────────────────────────
          _SectionHeader(title: 'CONNECTIVITY'),
          _SettingsCard(
            child: _TextRow(
              label: 'Sync Server URL',
              controller: _syncUrlController,
              hint: 'http://192.168.1.100:8080',
              keyboardType: TextInputType.url,
            ),
          ),

          const SizedBox(height: 40),

          // Version note
          const Center(
            child: Text(
              'GastroCore ODS  •  v1.0.0',
              style: TextStyle(fontSize: 13, color: OdsColors.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: OdsColors.textDim,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card wrapper
// ---------------------------------------------------------------------------

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: OdsColors.bgCard,
        borderRadius: BorderRadius.circular(kOdsRadiusMedium),
        border: Border.all(color: OdsColors.divider, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Text field row
// ---------------------------------------------------------------------------

class _TextRow extends StatelessWidget {
  const _TextRow({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: OdsColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: const TextStyle(
                fontSize: 16,
                color: OdsColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: OdsColors.textDim),
                filled: true,
                fillColor: OdsColors.bgCardAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(kOdsRadiusSmall),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Switch row
// ---------------------------------------------------------------------------

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: OdsColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: OdsColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: OdsColors.ready,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slider row
// ---------------------------------------------------------------------------

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: OdsColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              activeColor: OdsColors.preparing,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              format(value),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: OdsColors.textSecondary,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inner divider
// ---------------------------------------------------------------------------

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: OdsColors.divider,
    );
  }
}
