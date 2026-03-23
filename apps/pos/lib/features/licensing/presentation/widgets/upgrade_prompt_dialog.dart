/// Upgrade prompt shown when a user attempts to access a gated feature.
///
/// Displays the required tier, lists the features unlocked by that tier, and
/// provides a text field for the user to paste their license token.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/app_feature.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/license_tier.dart';
import 'package:gastrocore_pos/features/licensing/domain/repositories/license_repository.dart';
import 'package:gastrocore_pos/features/licensing/presentation/providers/license_provider.dart';

// ---------------------------------------------------------------------------
// Static helper
// ---------------------------------------------------------------------------

/// Show the upgrade dialog and return `true` if the user successfully activates
/// a new license.
Future<bool> showUpgradeDialog(
  BuildContext context, {
  required LicenseTier requiredTier,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _UpgradeDialog(requiredTier: requiredTier),
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

class _UpgradeDialog extends ConsumerStatefulWidget {
  const _UpgradeDialog({required this.requiredTier});
  final LicenseTier requiredTier;

  @override
  ConsumerState<_UpgradeDialog> createState() => _UpgradeDialogState();
}

class _UpgradeDialogState extends ConsumerState<_UpgradeDialog> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final token = _ctrl.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Please paste your license token.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(licenseNotifierProvider.notifier).activate(token);
      if (mounted) Navigator.of(context).pop(true);
    } on LicenseException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Activation failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tier = widget.requiredTier;
    final tierFeatures = AppFeature.values
        .where((f) => f.requiredTier == tier)
        .toList();

    return Dialog(
      backgroundColor: AppColors.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 480,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _tierColor(tier).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _tierColor(tier), width: 1),
                    ),
                    child: Text(
                      tier.badge,
                      style: TextStyle(
                        color: _tierColor(tier),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Upgrade to ${tier.displayName}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textDim),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Feature list
              if (tierFeatures.isNotEmpty) ...[
                const Text(
                  'Unlocked with this tier:',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ...tierFeatures.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 16, color: _tierColor(tier)),
                        const SizedBox(width: 8),
                        Text(
                          f.displayName,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Token input
              const Text(
                'License Token',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _ctrl,
                maxLines: 3,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Paste your license token here…',
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
                      if (data?.text != null) {
                        _ctrl.text = data!.text!;
                      }
                    },
                  ),
                ),
              ),

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                      color: AppColors.red, fontSize: 12),
                ),
              ],

              const SizedBox(height: 20),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _loading ? null : _activate,
                    style: FilledButton.styleFrom(
                      backgroundColor: _tierColor(tier),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Activate License'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _tierColor(LicenseTier tier) => switch (tier) {
        LicenseTier.free => AppColors.textDim,
        LicenseTier.starter => const Color(0xFF4CAF50),
        LicenseTier.professional => const Color(0xFF4C9EFF),
        LicenseTier.enterprise => const Color(0xFFB06EFF),
      };
}
