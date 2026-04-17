/// Staff live status placeholder — Sprint 1 Step 5 wires real data.
library;

import 'package:flutter/material.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.people_outline,
      title: 'Personel',
      subtitle: 'Sprint 1 Adım 5 — StaffApi.activeStaff ile bağlanacak.',
    );
  }
}
