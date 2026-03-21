/// Menu display settings dialog for GastroCore POS.
///
/// Allows the user to configure the product grid display options:
/// button size, display mode (picture vs color label), price visibility,
/// and sort order. Follows Stitch S04 design with no-border philosophy.
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Settings data model
// ---------------------------------------------------------------------------

/// Encapsulates all menu display settings.
class MenuDisplaySettings {
  final bool showPictures;
  final bool useBigButtons;
  final bool showPrice;
  final String sortMode;

  const MenuDisplaySettings({
    this.showPictures = true,
    this.useBigButtons = false,
    this.showPrice = true,
    this.sortMode = 'default',
  });

  MenuDisplaySettings copyWith({
    bool? showPictures,
    bool? useBigButtons,
    bool? showPrice,
    String? sortMode,
  }) {
    return MenuDisplaySettings(
      showPictures: showPictures ?? this.showPictures,
      useBigButtons: useBigButtons ?? this.useBigButtons,
      showPrice: showPrice ?? this.showPrice,
      sortMode: sortMode ?? this.sortMode,
    );
  }
}

// ---------------------------------------------------------------------------
// Public helper to show the dialog
// ---------------------------------------------------------------------------

/// Shows the menu display settings dialog.
///
/// Returns the updated [MenuDisplaySettings] if the user confirms,
/// or `null` if cancelled.
Future<MenuDisplaySettings?> showMenuSettingsDialog({
  required BuildContext context,
  required MenuDisplaySettings currentSettings,
}) {
  return showDialog<MenuDisplaySettings>(
    context: context,
    barrierColor: AppColors.bgOverlay,
    builder: (ctx) => _MenuSettingsDialogContent(
      initialSettings: currentSettings,
    ),
  );
}

// ---------------------------------------------------------------------------
// Dialog content
// ---------------------------------------------------------------------------

class _MenuSettingsDialogContent extends StatefulWidget {
  final MenuDisplaySettings initialSettings;

  const _MenuSettingsDialogContent({required this.initialSettings});

  @override
  State<_MenuSettingsDialogContent> createState() =>
      _MenuSettingsDialogContentState();
}

class _MenuSettingsDialogContentState
    extends State<_MenuSettingsDialogContent> {
  late bool _showPictures;
  late bool _useBigButtons;
  late bool _showPrice;
  late String _sortMode;

  @override
  void initState() {
    super.initState();
    _showPictures = widget.initialSettings.showPictures;
    _useBigButtons = widget.initialSettings.useBigButtons;
    _showPrice = widget.initialSettings.showPrice;
    _sortMode = widget.initialSettings.sortMode;
  }

  void _onConfirm() {
    Navigator.of(context).pop(MenuDisplaySettings(
      showPictures: _showPictures,
      useBigButtons: _useBigButtons,
      showPrice: _showPrice,
      sortMode: _sortMode,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 380,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Text(
                'Settings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),

            // Settings rows
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // Button size
                  _buildSettingRow(
                    label: 'Button size',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildRadioChip(
                          label: 'Big',
                          selected: _useBigButtons,
                          onTap: () =>
                              setState(() => _useBigButtons = true),
                        ),
                        const SizedBox(width: 8),
                        _buildRadioChip(
                          label: 'Small',
                          selected: !_useBigButtons,
                          onTap: () =>
                              setState(() => _useBigButtons = false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Display mode
                  _buildSettingRow(
                    label: 'Display',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildRadioChip(
                          label: 'Picture',
                          selected: _showPictures,
                          onTap: () =>
                              setState(() => _showPictures = true),
                        ),
                        const SizedBox(width: 8),
                        _buildRadioChip(
                          label: 'Color label',
                          selected: !_showPictures,
                          onTap: () =>
                              setState(() => _showPictures = false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Show price
                  _buildSettingRow(
                    label: 'Show price',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildRadioChip(
                          label: 'Yes',
                          selected: _showPrice,
                          onTap: () =>
                              setState(() => _showPrice = true),
                        ),
                        const SizedBox(width: 8),
                        _buildRadioChip(
                          label: 'No',
                          selected: !_showPrice,
                          onTap: () =>
                              setState(() => _showPrice = false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sort
                  _buildSettingRow(
                    label: 'Sort',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildRadioChip(
                          label: 'Default',
                          selected: _sortMode == 'default',
                          onTap: () =>
                              setState(() => _sortMode = 'default'),
                        ),
                        const SizedBox(width: 6),
                        _buildRadioChip(
                          label: 'Sales',
                          selected: _sortMode == 'sales',
                          onTap: () =>
                              setState(() => _sortMode = 'sales'),
                        ),
                        const SizedBox(width: 6),
                        _buildRadioChip(
                          label: 'A-Z',
                          selected: _sortMode == 'alphabetical',
                          onTap: () =>
                              setState(() => _sortMode = 'alphabetical'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  // Cancel
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Confirm
                  Expanded(
                    child: GestureDetector(
                      onTap: _onConfirm,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primaryContainer,
                            ],
                            begin: Alignment(-0.7, -0.7),
                            end: Alignment(0.7, 0.7),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'Confirm',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0D1B3A),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildSettingRow({
    required String label,
    required Widget child,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        child,
      ],
    );
  }

  Widget _buildRadioChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentDim : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.accent : AppColors.textSecondary,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
