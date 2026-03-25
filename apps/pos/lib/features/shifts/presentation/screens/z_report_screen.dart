/// Z-Report Screen — live day-close report for the current shift.
///
/// Shows:
///   - Revenue summary (gross, net, discounts)
///   - Cash vs card breakdown
///   - Transaction count, average ticket, void count
///   - MWST breakdown (A=8.1% dine-in, B=2.6% takeaway)
///   - Top 5 selling items
///
/// Actions:
///   - Print Z-Report (Tagesabschluss)
///   - Print X-Report (Zwischenbericht — no register reset)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/printing/models/print_models.dart';
import 'package:gastrocore_pos/core/printing/providers/print_use_case_provider.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/shift_summary_entity.dart';
import 'package:gastrocore_pos/features/shifts/presentation/providers/z_report_provider.dart';

class ZReportScreen extends ConsumerWidget {
  const ZReportScreen({super.key});

  // -------------------------------------------------------------------------
  // Formatting helpers
  // -------------------------------------------------------------------------

  static String _chf(int cents) {
    final isNeg = cents < 0;
    final abs = cents.abs();
    return '${isNeg ? '-' : ''}CHF ${(abs / 100).toStringAsFixed(2)}';
  }

  static String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}'
      '.${dt.month.toString().padLeft(2, '0')}'
      '.${dt.year}';

  static String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}'
      ':${dt.minute.toString().padLeft(2, '0')}';

  static String _fmtQty(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  // -------------------------------------------------------------------------
  // Print
  // -------------------------------------------------------------------------

  Future<void> _printReport(
    BuildContext context,
    WidgetRef ref,
    ZReportStats stats, {
    required bool isZReport,
  }) async {
    final reportPaymentBreakdown = {
      for (final e in stats.paymentBreakdown.entries)
        PaymentBreakdownLine.labelFor(e.key): e.value,
    };

    final mwstEntries = stats.mwstEntries
        .map(
          (e) => MwStReportEntry(
            code: MwStCode.fromCode(e.code),
            grossAmount: e.grossCents,
          ),
        )
        .toList();

    final data = ShiftReportData(
      reportTitle: isZReport ? 'Z-RAPPORT' : 'X-RAPPORT',
      reportNo: 0,
      cashierName: null,
      terminalNo: stats.shift.deviceId,
      shiftStart: stats.shift.openedAt,
      shiftEnd: isZReport ? DateTime.now() : null,
      printedAt: DateTime.now(),
      grossSales: stats.totalRevenueCents,
      totalDiscount: stats.discountTotalCents,
      netSales: stats.netRevenueCents,
      netRevenue: stats.netRevenueCents,
      paymentBreakdown: reportPaymentBreakdown,
      mwstEntries: mwstEntries,
      orderCount: stats.totalOrders,
      voidCount: stats.voidCount,
      openingFloat: stats.shift.openingCash,
    );

    final useCase = ref.read(printReportUseCaseProvider);
    final ok = isZReport
        ? await useCase.printZReport(data)
        : await useCase.printXReport(data);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (isZReport ? 'Z-Rapport gedruckt.' : 'X-Rapport gedruckt.')
                : 'Drucker nicht erreichbar.',
          ),
          backgroundColor: ok ? AppColors.green : AppColors.red,
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(zReportStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _TopBar(
            onBack: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/settings');
              }
            },
          ),
          Expanded(
            child: statsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Fehler: $e',
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
              data: (stats) {
                if (stats == null) {
                  return const Center(
                    child: Text(
                      'Kein aktiver Shift.\nBitte Shift öffnen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textDim,
                        fontSize: 15,
                      ),
                    ),
                  );
                }
                return _ReportBody(
                  stats: stats,
                  onPrintZ: () => _printReport(
                    context,
                    ref,
                    stats,
                    isZReport: true,
                  ),
                  onPrintX: () => _printReport(
                    context,
                    ref,
                    stats,
                    isZReport: false,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: AppColors.surface,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Z-Rapport / Tagesabschluss',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.orangeDim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.orange,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Report body
// ---------------------------------------------------------------------------

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.stats,
    required this.onPrintZ,
    required this.onPrintX,
  });

  final ZReportStats stats;
  final VoidCallback onPrintZ;
  final VoidCallback onPrintX;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: stats
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _shiftHeader(),
                const SizedBox(height: 20),
                _revenueCard(),
                const SizedBox(height: 16),
                _paymentsCard(),
                const SizedBox(height: 16),
                _transactionCard(),
                const SizedBox(height: 16),
                if (stats.mwstEntries.isNotEmpty) ...[
                  _mwstCard(),
                  const SizedBox(height: 16),
                ],
                if (stats.topItems.isNotEmpty) _topItemsCard(),
              ],
            ),
          ),
        ),
        // Right: actions
        Container(
          width: 240,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Aktionen',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDim,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),
              _ActionButton(
                label: 'Z-Rapport drucken',
                sublabel: 'Tagesabschluss',
                icon: Icons.print_rounded,
                color: AppColors.accent,
                onTap: onPrintZ,
              ),
              const SizedBox(height: 10),
              _ActionButton(
                label: 'X-Rapport drucken',
                sublabel: 'Zwischenbericht',
                icon: Icons.receipt_long_rounded,
                color: AppColors.orange,
                onTap: onPrintX,
              ),
              const SizedBox(height: 20),
              const Divider(color: AppColors.surfaceContainerHigh),
              const SizedBox(height: 12),
              Text(
                'Aktualisiert: ${ZReportScreen._fmtTime(stats.generatedAt)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textDim,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- Cards ----

  Widget _shiftHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Shift: ${ZReportScreen._fmtDate(stats.shift.openedAt)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Geöffnet: ${ZReportScreen._fmtTime(stats.shift.openedAt)}  •  '
                'Terminal: ${stats.shift.deviceId}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textDim,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _revenueCard() {
    return _StatCard(
      title: 'UMSATZ',
      children: [
        _StatRow(
          'Brutto-Umsatz',
          ZReportScreen._chf(stats.totalRevenueCents),
          bold: true,
        ),
        if (stats.discountTotalCents > 0)
          _StatRow(
            'Rabatte',
            '- ${ZReportScreen._chf(stats.discountTotalCents)}',
            valueColor: AppColors.orange,
          ),
        if (stats.discountTotalCents > 0) ...[
          const Divider(color: AppColors.surfaceContainerHigh, height: 16),
          _StatRow(
            'Netto-Umsatz',
            ZReportScreen._chf(stats.netRevenueCents),
            bold: true,
          ),
        ],
        const Divider(color: AppColors.surfaceContainerHigh, height: 16),
        _StatRow(
          'MWST Total',
          ZReportScreen._chf(stats.taxTotalCents),
          valueColor: AppColors.textDim,
        ),
      ],
    );
  }

  Widget _paymentsCard() {
    final entries = stats.paymentBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _StatCard(
      title: 'ZAHLUNGEN',
      children: [
        for (final e in entries)
          _StatRow(
            PaymentBreakdownLine.labelFor(e.key),
            ZReportScreen._chf(e.value),
          ),
        if (entries.isNotEmpty) ...[
          const Divider(color: AppColors.surfaceContainerHigh, height: 16),
          _StatRow(
            'Bar',
            ZReportScreen._chf(stats.cashTotal),
            label2: 'Karte/Digital',
            value2: ZReportScreen._chf(stats.cardTotal),
          ),
        ],
      ],
    );
  }

  Widget _transactionCard() {
    return _StatCard(
      title: 'STATISTIK',
      children: [
        _StatRow('Bons gesamt', stats.totalOrders.toString()),
        _StatRow(
          'Durchschnitt / Bon',
          ZReportScreen._chf(stats.avgOrderCents),
        ),
        _StatRow(
          'Stornierungen',
          stats.voidCount.toString(),
          valueColor:
              stats.voidCount > 0 ? AppColors.orange : AppColors.textDim,
        ),
      ],
    );
  }

  Widget _mwstCard() {
    return _StatCard(
      title: 'MWST-ABRECHNUNG',
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              _mwstCol('Cod', 40, left: true),
              _mwstCol('Satz', 50, left: true),
              _mwstCol('Netto', 90),
              _mwstCol('MwSt', 90),
              _mwstCol('Brutto', 90),
            ],
          ),
        ),
        const Divider(color: AppColors.surfaceContainerHigh, height: 8),
        for (final e in stats.mwstEntries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                _mwstCol(e.code, 40, left: true),
                _mwstCol('${e.rate.toStringAsFixed(1)}%', 50, left: true),
                _mwstCol(
                  ZReportScreen._chf(e.netCents).replaceFirst('CHF ', ''),
                  90,
                ),
                _mwstCol(
                  ZReportScreen._chf(e.taxCents).replaceFirst('CHF ', ''),
                  90,
                  valueColor: AppColors.orange,
                ),
                _mwstCol(
                  ZReportScreen._chf(e.grossCents).replaceFirst('CHF ', ''),
                  90,
                ),
              ],
            ),
          ),
        const Divider(color: AppColors.surfaceContainerHigh, height: 8),
        Row(
          children: [
            _mwstCol('Total', 40, left: true, bold: true),
            _mwstCol('', 50, left: true),
            _mwstCol(
              ZReportScreen._chf(
                stats.mwstEntries.fold(0, (s, e) => s + e.netCents),
              ).replaceFirst('CHF ', ''),
              90,
              bold: true,
            ),
            _mwstCol(
              ZReportScreen._chf(
                stats.mwstEntries.fold(0, (s, e) => s + e.taxCents),
              ).replaceFirst('CHF ', ''),
              90,
              bold: true,
            ),
            _mwstCol(
              ZReportScreen._chf(
                stats.mwstEntries.fold(0, (s, e) => s + e.grossCents),
              ).replaceFirst('CHF ', ''),
              90,
              bold: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _mwstCol(
    String text,
    double width, {
    bool left = false,
    bool bold = false,
    Color? valueColor,
  }) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: left ? TextAlign.left : TextAlign.right,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: valueColor ?? AppColors.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _topItemsCard() {
    return _StatCard(
      title: 'TOP ARTIKEL',
      children: [
        for (final item in stats.topItems)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '×${ZReportScreen._fmtQty(item.quantity)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDim,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  ZReportScreen._chf(item.revenueCents),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable widgets
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textDim,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(
    this.label,
    this.value, {
    this.bold = false,
    this.valueColor,
    this.label2,
    this.value2,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;
  final String? label2;
  final String? value2;

  @override
  Widget build(BuildContext context) {
    if (label2 != null && value2 != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: _labelText(label, bold: bold),
            ),
            _valueText(value, bold: bold, color: valueColor),
            const SizedBox(width: 20),
            _labelText(label2!),
            const SizedBox(width: 8),
            _valueText(value2!),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: _labelText(label, bold: bold)),
          _valueText(value, bold: bold, color: valueColor),
        ],
      ),
    );
  }

  Widget _labelText(String text, {bool bold = false}) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: bold ? AppColors.textPrimary : AppColors.textSecondary,
        ),
      );

  Widget _valueText(String text, {bool bold = false, Color? color}) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
          color: color ?? (bold ? AppColors.textPrimary : AppColors.textSecondary),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textDim,
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
