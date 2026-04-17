/// Z-report screen placeholder — Sprint 1 Step 3 wires real data.
library;

import 'package:flutter/material.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';

class ZReportScreen extends StatelessWidget {
  const ZReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.receipt_long,
      title: 'Günlük Özet (Z-Rapor)',
      subtitle: 'Sprint 1 Adım 3 — ReportApi.zReport ile bağlanacak.',
    );
  }
}
