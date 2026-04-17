/// Settings placeholder — Sprint 1 Step 4 adds notifications toggle.
library;

import 'package:flutter/material.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.settings_outlined,
      title: 'Ayarlar',
      subtitle:
          'Sprint 1 Adım 4 — Bildirim toggle, dil, tenant seçici buraya gelecek.',
    );
  }
}
