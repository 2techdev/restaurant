/// License management screen for GastroCore POS.
///
/// Shows the current plan, expiry info, the enabled feature set, and a
/// token activation form. Reached from Settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/license/license_models.dart';
import 'package:gastrocore_pos/features/license/license_provider.dart';
import 'package:gastrocore_pos/features/licensing/domain/repositories/license_repository.dart';
import 'package:gastrocore_pos/features/licensing/presentation/providers/license_provider.dart'
    as legacy;

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class LicenseScreen extends ConsumerStatefulWidget {
  const LicenseScreen({super.key});

  @override
  ConsumerState<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends ConsumerState<LicenseScreen> {
  final _tokenCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

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
      await ref.read(legacy.licenseNotifierProvider.notifier).activate(token);
      _tokenCtrl.clear();
      if (mounted) {
        setState(() => _success = 'License activated successfully.');
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: const Text('Deactivate License',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This will revert your plan to Free. You can re-activate at any time.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(legacy.licenseNotifierProvider.notifier).deactivate();
    if (mounted) {
      setState(() {
        _success = 'License deactivated. Running on Free plan.';
        _error = null;
      });
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) _tokenCtrl.text = data!.text!;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(licenseTokenProvider);
    final edition = ref.watch(licenseEditionProvider);
    final enabledFlags = ref.watch(enabledFlagsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainer,
        title: const Text('License',
            style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Current plan card
          _PlanCard(token: token, edition: edition),
          const SizedBox(height: 24),

          // Feature flags grid
          _FeatureFlagsGrid(enabledFlags: enabledFlags),
          const SizedBox(height: 24),

          // Token activation
          _TokenSection(
            ctrl: _tokenCtrl,
            loading: _loading,
            error: _error,
            success: _success,
            onActivate: _activate,
            onPaste: _paste,
          ),

          // Deactivate option (only when a license is installed)
          if (token != null) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: _deactivate,
                icon: const Icon(Icons.cancel_outlined,
                    size: 16, color: AppColors.textDim),
                label: const Text('Deactivate license',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13)),
              ),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PlanCard
// ---------------------------------------------------------------------------

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.token, required this.edition});

  final LicenseToken? token;
  final LicenseEdition edition;

  @override
  Widget build(BuildContext context) {
    final color = _editionColor(edition);
    final dateFormat = DateFormat('dd MMM yyyy');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withOpacity(0.6)),
                ),
                child: Text(
                  edition.badge,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${edition.displayName} Plan',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (token != null) ...[
            const SizedBox(height: 16),
            if (token!.customerName.isNotEmpty)
              _InfoRow(
                icon: Icons.business_rounded,
                label: 'Licensed to',
                value: token!.customerName,
              ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.calendar_today_rounded,
              label: 'Issued',
              value: dateFormat.format(token!.issuedAt),
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: token!.isExpired
                  ? Icons.warning_amber_rounded
                  : Icons.event_available_rounded,
              label: token!.isExpired ? 'Expired' : 'Expires',
              value: token!.isExpired
                  ? '${dateFormat.format(token!.expiresAt)} (expired)'
                  : '${dateFormat.format(token!.expiresAt)} '
                      '(${token!.daysUntilExpiry} days)',
              valueColor: token!.isExpired ? AppColors.red : null,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.devices_rounded,
              label: 'Device limit',
              value: '${token!.deviceLimit} device${token!.deviceLimit == 1 ? '' : 's'}',
            ),
          ] else ...[
            const SizedBox(height: 12),
            const Text(
              'No license installed. Activate a token below to unlock features.',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Color _editionColor(LicenseEdition edition) => switch (edition) {
        LicenseEdition.free => AppColors.textDim,
        LicenseEdition.starter => const Color(0xFF4CAF50),
        LicenseEdition.pro => const Color(0xFF4C9EFF),
        LicenseEdition.enterprise => const Color(0xFFB06EFF),
      };
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textDim),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _FeatureFlagsGrid
// ---------------------------------------------------------------------------

class _FeatureFlagsGrid extends StatelessWidget {
  const _FeatureFlagsGrid({required this.enabledFlags});

  final Set<FeatureFlag> enabledFlags;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Features',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        // Group by required edition
        for (final edition in LicenseEdition.values.skip(1)) ...[
          _EditionGroup(
            edition: edition,
            flags: FeatureFlag.values
                .where((f) => f.requiredEdition == edition)
                .toList(),
            enabledFlags: enabledFlags,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _EditionGroup extends StatelessWidget {
  const _EditionGroup({
    required this.edition,
    required this.flags,
    required this.enabledFlags,
  });

  final LicenseEdition edition;
  final List<FeatureFlag> flags;
  final Set<FeatureFlag> enabledFlags;

  @override
  Widget build(BuildContext context) {
    final color = _editionColor(edition);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surfaceContainerHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    edition.badge,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(edition.displayName,
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Divider(
              height: 1, color: AppColors.surfaceContainerHigh),
          for (final flag in flags)
            _FlagRow(flag: flag, enabled: enabledFlags.contains(flag)),
        ],
      ),
    );
  }

  Color _editionColor(LicenseEdition edition) => switch (edition) {
        LicenseEdition.free => AppColors.textDim,
        LicenseEdition.starter => const Color(0xFF4CAF50),
        LicenseEdition.pro => const Color(0xFF4C9EFF),
        LicenseEdition.enterprise => const Color(0xFFB06EFF),
      };
}

class _FlagRow extends StatelessWidget {
  const _FlagRow({required this.flag, required this.enabled});

  final FeatureFlag flag;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle_rounded : Icons.lock_rounded,
            size: 18,
            color: enabled
                ? const Color(0xFF4CAF50)
                : AppColors.textDim,
          ),
          const SizedBox(width: 12),
          Text(
            flag.displayName,
            style: TextStyle(
              color:
                  enabled ? AppColors.textPrimary : AppColors.textDim,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _TokenSection
// ---------------------------------------------------------------------------

class _TokenSection extends StatelessWidget {
  const _TokenSection({
    required this.ctrl,
    required this.loading,
    required this.error,
    required this.success,
    required this.onActivate,
    required this.onPaste,
  });

  final TextEditingController ctrl;
  final bool loading;
  final String? error;
  final String? success;
  final VoidCallback onActivate;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceContainerHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Activate License',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Paste the license token you received from GastroCore.',
            style:
                TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            maxLines: 3,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'eyJ...',
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
                onPressed: onPaste,
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!,
                style: const TextStyle(
                    color: AppColors.red, fontSize: 12)),
          ],
          if (success != null) ...[
            const SizedBox(height: 8),
            Text(success!,
                style: const TextStyle(
                    color: Color(0xFF4CAF50), fontSize: 12)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : onActivate,
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.verified_rounded, size: 18),
              label: Text(loading ? 'Activating…' : 'Activate License'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4C9EFF),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
