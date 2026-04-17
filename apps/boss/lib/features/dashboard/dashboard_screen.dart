/// Live dashboard placeholder — Sprint 1 Step 2 wires real data.
library;

import 'package:flutter/material.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.show_chart,
      title: 'Canlı Pano',
      subtitle: 'Sprint 1 Adım 2 — DashboardApi.getLiveMetrics ile bağlanacak.',
    );
  }
}
