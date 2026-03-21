/// Analytics & Reporting Screen for GastroCore POS.
///
/// Full reporting dashboard with:
///   • Date range selector (Bugün / Bu Hafta / Bu Ay / Özel)
///   • KPI cards: revenue, orders, avg order, cancel rate, table occupancy
///   • Daily revenue trend line chart (fl_chart)
///   • Payment method breakdown (pie chart + legend)
///   • Hourly order density heatmap (bar chart)
///   • Top 10 selling products (horizontal bar chart)
///   • Staff performance table
///   • MWST (Swiss VAT) report table
///   • Pull-to-refresh
///   • Export as PDF and Excel
library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/dashboard/domain/entities/analytics_report.dart';
import 'package:gastrocore_pos/features/dashboard/presentation/providers/analytics_provider.dart';
import 'package:gastrocore_pos/features/dashboard/presentation/utils/pdf_exporter.dart';
import 'package:gastrocore_pos/features/dashboard/presentation/utils/excel_exporter.dart';

// ---------------------------------------------------------------------------
// Formatters
// ---------------------------------------------------------------------------

final _chf = NumberFormat.currency(locale: 'de_CH', symbol: 'CHF ', decimalDigits: 2);
final _chfCompact = NumberFormat.currency(locale: 'de_CH', symbol: 'CHF ', decimalDigits: 0);
final _dateFmt = DateFormat('dd.MM.yy');
final _pct = NumberFormat('0.0%');

String _fChf(int cents) => _chf.format(cents / 100);
String _fChfCompact(int cents) => _chfCompact.format(cents / 100);

// ---------------------------------------------------------------------------
// AnalyticsScreen
// ---------------------------------------------------------------------------

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  bool _exporting = false;

  Future<void> _refresh() async {
    ref.invalidate(analyticsReportProvider);
  }

  Future<void> _exportPdf(AnalyticsReport report) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await PdfExporter.shareReport(report);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hatası: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportExcel(AnalyticsReport report) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await ExcelExporter.exportReport(report);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Excel kaydedildi: $path'),
            backgroundColor: AppColors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel hatası: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      locale: const Locale('tr', 'TR'),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: Color(0xFF0D1B2A),
            surface: AppColors.surfaceContainer,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (result != null) {
      ref
          .read(analyticsDateProvider.notifier)
          .select(AnalyticsPreset.custom, custom: result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateState = ref.watch(analyticsDateProvider);
    final reportAsync = ref.watch(analyticsReportProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _Header(
            dateState: dateState,
            exporting: _exporting,
            onPreset: (p) =>
                ref.read(analyticsDateProvider.notifier).select(p),
            onCustom: _pickCustomRange,
            onExportPdf: reportAsync.valueOrNull != null
                ? () => _exportPdf(reportAsync.value!)
                : null,
            onExportExcel: reportAsync.valueOrNull != null
                ? () => _exportExcel(reportAsync.value!)
                : null,
            onBack: () => context.pop(),
          ),
          Expanded(
            child: reportAsync.when(
              loading: () => const _LoadingBody(),
              error: (e, _) => _ErrorBody(error: e, onRetry: _refresh),
              data: (report) => RefreshIndicator(
                onRefresh: _refresh,
                color: AppColors.primary,
                backgroundColor: AppColors.surfaceContainer,
                child: _ReportBody(report: report),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final AnalyticsDateState dateState;
  final bool exporting;
  final ValueChanged<AnalyticsPreset> onPreset;
  final VoidCallback onCustom;
  final VoidCallback? onExportPdf;
  final VoidCallback? onExportExcel;
  final VoidCallback onBack;

  const _Header({
    required this.dateState,
    required this.exporting,
    required this.onPreset,
    required this.onCustom,
    required this.onExportPdf,
    required this.onExportExcel,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: AppColors.surface,
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: const Icon(Icons.arrow_back_rounded,
                size: 20, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 16),
          const Text(
            'Analytics & Raporlar',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 24),
          // Date preset chips
          ...[
            AnalyticsPreset.today,
            AnalyticsPreset.thisWeek,
            AnalyticsPreset.thisMonth,
          ].map((p) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _PresetChip(
                  label: _presetLabel(p),
                  selected: dateState.preset == p,
                  onTap: () => onPreset(p),
                ),
              )),
          _PresetChip(
            label: dateState.preset == AnalyticsPreset.custom
                ? '${DateFormat('dd.MM').format(dateState.filter.start)} – '
                    '${DateFormat('dd.MM').format(dateState.filter.end.subtract(const Duration(days: 1)))}'
                : 'Özel',
            selected: dateState.preset == AnalyticsPreset.custom,
            onTap: onCustom,
            icon: Icons.calendar_month_rounded,
          ),
          const Spacer(),
          if (exporting)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            )
          else ...[
            _ExportButton(
              icon: Icons.picture_as_pdf_rounded,
              label: 'PDF',
              onTap: onExportPdf,
            ),
            const SizedBox(width: 8),
            _ExportButton(
              icon: Icons.table_chart_rounded,
              label: 'Excel',
              onTap: onExportExcel,
            ),
          ],
        ],
      ),
    );
  }

  static String _presetLabel(AnalyticsPreset p) => switch (p) {
        AnalyticsPreset.today => 'Bugün',
        AnalyticsPreset.thisWeek => 'Bu Hafta',
        AnalyticsPreset.thisMonth => 'Bu Ay',
        AnalyticsPreset.custom => 'Özel',
      };
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(color: AppColors.primary.withOpacity(0.4), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13,
                  color: selected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.primary : AppColors.textSecondary,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ExportButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.surfaceContainerHigh
              : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14,
                color: enabled
                    ? AppColors.textSecondary
                    : AppColors.textDim),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: enabled ? AppColors.textSecondary : AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading & Error states
// ---------------------------------------------------------------------------

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
          SizedBox(height: 16),
          Text('Veriler yükleniyor...',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorBody({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.red),
          const SizedBox(height: 12),
          Text(
            'Veri yüklenemedi',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text('$error',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Tekrar Dene',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Report body
// ---------------------------------------------------------------------------

class _ReportBody extends StatelessWidget {
  final AnalyticsReport report;

  const _ReportBody({required this.report});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI cards
          _KpiRow(report: report),
          const SizedBox(height: 20),

          // Trend chart + Payment pie (side by side)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: _TrendChart(report: report)),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: _PaymentPieCard(report: report)),
            ],
          ),
          const SizedBox(height: 20),

          // Hourly heatmap (full width)
          _HourlyHeatmap(report: report),
          const SizedBox(height: 20),

          // Top products + Staff (side by side)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 55, child: _TopProductsCard(report: report)),
              const SizedBox(width: 16),
              Expanded(flex: 45, child: _StaffPerformanceCard(report: report)),
            ],
          ),
          const SizedBox(height: 20),

          // MWST full width
          _MwstCard(report: report),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KPI Row
// ---------------------------------------------------------------------------

class _KpiRow extends StatelessWidget {
  final AnalyticsReport report;
  const _KpiRow({required this.report});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            icon: Icons.payments_rounded,
            label: 'Toplam Ciro',
            value: _fChfCompact(report.totalRevenueCents),
            color: AppColors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _KpiCard(
            icon: Icons.receipt_long_rounded,
            label: 'Tamamlanan',
            value: report.completedOrderCount.toString(),
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _KpiCard(
            icon: Icons.calculate_rounded,
            label: 'Ort. Sipariş',
            value: _fChfCompact(report.avgOrderCents),
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _KpiCard(
            icon: Icons.cancel_rounded,
            label: 'İptal Oranı',
            value: _pct.format(report.cancellationRate),
            color: report.cancellationRate > 0.1
                ? AppColors.orange
                : AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _KpiCard(
            icon: Icons.table_bar_rounded,
            label: 'Masa Doluluk',
            value: _pct.format(report.tableOccupancyRate),
            color: AppColors.purple,
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trend Line Chart
// ---------------------------------------------------------------------------

class _TrendChart extends StatefulWidget {
  final AnalyticsReport report;
  const _TrendChart({required this.report});

  @override
  State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final points = widget.report.dailyTrend;
    if (points.isEmpty) return _emptyCard('Günlük Trend', 'Veri bulunamadı');

    final maxY = points
        .map((p) => p.revenueCents)
        .reduce(math.max)
        .toDouble();
    final chartMax = maxY < 1 ? 100.0 : maxY * 1.15;

    final spots = points.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.revenueCents.toDouble());
    }).toList();

    return _Card(
      title: 'Günlük Gelir Trendi',
      height: 220,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: chartMax / 4,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.surfaceContainerHigh,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 60,
                interval: chartMax / 4,
                getTitlesWidget: (v, _) => Text(
                  _fChfCompact(v.toInt()),
                  style: const TextStyle(
                      fontSize: 9, color: AppColors.textDim),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: math.max(1, (points.length / 6).ceilToDouble()),
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _dateFmt.format(points[idx].date),
                      style: const TextStyle(
                          fontSize: 9, color: AppColors.textDim),
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: 0,
          maxY: chartMax,
          lineTouchData: LineTouchData(
            touchCallback: (evt, resp) {
              if (resp?.lineBarSpots != null) {
                setState(() {
                  _touchedIndex =
                      resp!.lineBarSpots!.first.spotIndex;
                });
              }
            },
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((s) {
                final p = points[s.spotIndex];
                return LineTooltipItem(
                  '${_dateFmt.format(p.date)}\n${_fChf(p.revenueCents)}\n${p.orderCount} sipariş',
                  const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: AppColors.primary,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (s, _, __, idx) => FlDotCirclePainter(
                  radius: idx == _touchedIndex ? 5 : 3,
                  color: AppColors.primary,
                  strokeWidth: 2,
                  strokeColor: AppColors.surfaceDim,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withOpacity(0.18),
                    AppColors.primary.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 400),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment Pie Chart
// ---------------------------------------------------------------------------

class _PaymentPieCard extends StatefulWidget {
  final AnalyticsReport report;
  const _PaymentPieCard({required this.report});

  @override
  State<_PaymentPieCard> createState() => _PaymentPieCardState();
}

class _PaymentPieCardState extends State<_PaymentPieCard> {
  int _touchedIndex = -1;

  static const _colors = [
    AppColors.primary,
    AppColors.green,
    AppColors.orange,
    AppColors.purple,
    AppColors.yellow,
  ];

  static const _labels = {
    'cash': 'Nakit',
    'credit_card': 'Kredi Kartı',
    'debit_card': 'Banka Kartı',
    'twint': 'TWINT',
    'other': 'Diğer',
  };

  @override
  Widget build(BuildContext context) {
    final payments = widget.report.paymentBreakdown;
    if (payments.isEmpty) {
      return _emptyCard('Ödeme Dağılımı', 'Veri bulunamadı');
    }

    final total =
        payments.fold<int>(0, (s, p) => s + p.amountCents);

    return _Card(
      title: 'Ödeme Yöntemleri',
      height: 220,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (evt, resp) {
                    setState(() {
                      _touchedIndex =
                          resp?.touchedSection?.touchedSectionIndex ?? -1;
                    });
                  },
                ),
                borderData: FlBorderData(show: false),
                sectionsSpace: 2,
                centerSpaceRadius: 32,
                sections: payments.asMap().entries.map((e) {
                  final i = e.key;
                  final p = e.value;
                  final touched = i == _touchedIndex;
                  final pct = total > 0 ? p.amountCents / total : 0.0;
                  return PieChartSectionData(
                    color: _colors[i % _colors.length],
                    value: p.amountCents.toDouble(),
                    title: touched
                        ? '${(pct * 100).toStringAsFixed(1)}%'
                        : '',
                    radius: touched ? 54 : 46,
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: payments.asMap().entries.map((e) {
                final i = e.key;
                final p = e.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _colors[i % _colors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _labels[p.method] ?? p.method,
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary),
                            ),
                            Text(
                              _fChfCompact(p.amountCents),
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hourly Heatmap (BarChart)
// ---------------------------------------------------------------------------

class _HourlyHeatmap extends StatelessWidget {
  final AnalyticsReport report;
  const _HourlyHeatmap({required this.report});

  @override
  Widget build(BuildContext context) {
    final hours = report.hourlySales;
    final maxOrders =
        hours.map((h) => h.orderCount).reduce(math.max);
    if (maxOrders == 0) {
      return _emptyCard('Saatlik Yoğunluk', 'Bu dönemde sipariş yok');
    }

    return _Card(
      title: 'Saatlik Sipariş Yoğunluğu',
      height: 160,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxOrders.toDouble() * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, __) {
                final h = hours[group.x];
                return BarTooltipItem(
                  '${h.hour.toString().padLeft(2, '0')}:00\n'
                  '${h.orderCount} sipariş\n${_fChf(h.amountCents)}',
                  const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                getTitlesWidget: (v, _) {
                  final h = v.toInt();
                  if (h % 3 != 0) return const SizedBox.shrink();
                  return Text(
                    '${h.toString().padLeft(2, '0')}h',
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.textDim),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: hours.map((h) {
            final intensity = maxOrders > 0
                ? h.orderCount / maxOrders
                : 0.0;
            final color = Color.lerp(
              AppColors.primary.withOpacity(0.25),
              AppColors.primary,
              intensity,
            )!;
            return BarChartGroupData(
              x: h.hour,
              barRods: [
                BarChartRodData(
                  toY: h.orderCount.toDouble(),
                  color: color,
                  width: 10,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3)),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top Products (Horizontal Bar Chart)
// ---------------------------------------------------------------------------

class _TopProductsCard extends StatelessWidget {
  final AnalyticsReport report;
  const _TopProductsCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final products = report.topProducts;
    if (products.isEmpty) {
      return _emptyCard('En Çok Satan Ürünler', 'Veri bulunamadı');
    }

    final maxRevenue = products
        .map((p) => p.revenueCents)
        .reduce(math.max)
        .toDouble();

    return _Card(
      title: 'En Çok Satan Ürünler (Top 10)',
      child: Column(
        children: products.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          final ratio = maxRevenue > 0 ? p.revenueCents / maxRevenue : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i < 3
                            ? AppColors.primary.withOpacity(0.15)
                            : AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: i < 3
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.productName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _fChfCompact(p.revenueCents),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '×${p.quantity.toStringAsFixed(p.quantity % 1 == 0 ? 0 : 1)}',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: ratio,
                    backgroundColor: AppColors.surfaceContainerHigh,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(i < 3
                            ? AppColors.primary
                            : AppColors.primary.withOpacity(0.5)),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Staff Performance
// ---------------------------------------------------------------------------

class _StaffPerformanceCard extends StatelessWidget {
  final AnalyticsReport report;
  const _StaffPerformanceCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final staff = report.staffPerformance;
    if (staff.isEmpty) {
      return _emptyCard('Personel Performansı', 'Veri bulunamadı');
    }

    return _Card(
      title: 'Personel Performansı',
      child: Column(
        children: [
          // Header row
          Row(
            children: const [
              Expanded(flex: 3, child: _ColHeader('Personel')),
              Expanded(flex: 2, child: _ColHeader('Sipariş')),
              Expanded(flex: 3, child: _ColHeader('Ciro')),
              Expanded(flex: 2, child: _ColHeader('Ort. Süre')),
            ],
          ),
          const SizedBox(height: 8),
          // Data rows
          ...staff.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                s.waiterName.isNotEmpty
                                    ? s.waiterName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.waiterName,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${s.orderCount}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _fChfCompact(s.revenueCents),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.green),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        s.avgDurationMinutes > 0
                            ? '${s.avgDurationMinutes} dk'
                            : '–',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  final String label;
  const _ColHeader(this.label);

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.textDim,
          letterSpacing: 0.2,
        ),
      );
}

// ---------------------------------------------------------------------------
// MWST Report
// ---------------------------------------------------------------------------

class _MwstCard extends StatelessWidget {
  final AnalyticsReport report;
  const _MwstCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final mwst = report.mwstReport;
    if (mwst.isEmpty) {
      return _emptyCard('MWST Raporu', 'Bu dönemde tamamlanan sipariş yok');
    }

    final totalGross =
        mwst.fold<int>(0, (s, m) => s + m.grossRevenueCents);
    final totalTax = mwst.fold<int>(0, (s, m) => s + m.taxCents);
    final totalNet = totalGross - totalTax;

    return _Card(
      title: 'MWST Raporu (İsviçre KDV)',
      child: Column(
        children: [
          // Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: const [
                Expanded(flex: 3, child: _ColHeader('Kategori')),
                Expanded(flex: 2, child: _ColHeader('Brüt (CHF)')),
                Expanded(flex: 2, child: _ColHeader('MWST (CHF)')),
                Expanded(flex: 2, child: _ColHeader('Net (CHF)')),
                Expanded(flex: 2, child: _ColHeader('Oran %')),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Rows
          ...mwst.map(
            (m) => Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: const Border(
                  bottom: BorderSide(
                      color: AppColors.surfaceContainerHigh, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      m.label,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _fChfCompact(m.grossRevenueCents),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textPrimary),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _fChfCompact(m.taxCents),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.orange),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _fChfCompact(m.netRevenueCents),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.green),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${m.effectiveRatePct.toStringAsFixed(1)}%',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Totals row
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8)),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text(
                    'TOPLAM',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    _fChfCompact(totalGross),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    _fChfCompact(totalTax),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.orange),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    _fChfCompact(totalNet),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green),
                  ),
                ),
                const Expanded(flex: 2, child: SizedBox.shrink()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared card containers
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  final double? height;

  const _Card({required this.title, required this.child, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Empty-state card for when a section has no data.
Widget _emptyCard(String title, String message) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textDim),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
