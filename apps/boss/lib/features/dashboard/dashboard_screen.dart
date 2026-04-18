/// Live dashboard — today's revenue, tables, orders, covers, top 5.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';
import 'package:intl/intl.dart';

import 'dashboard_models.dart';
import 'dashboard_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(liveMetricsProvider);
    return metrics.when(
      data: (m) => _DashboardBody(metrics: m),
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (e, _) => GastrocoreErrorWidget(
        message: 'Canlı veriler alınamadı: $e',
        onRetry: () => ref.invalidate(liveMetricsProvider),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  final LiveMetrics metrics;
  const _DashboardBody({required this.metrics});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen to payment events solely to drive the pulse animation; the
    // metrics card refreshes from `liveMetricsProvider` on its own cadence.
    ref.listen<AsyncValue<PaymentEvent>>(paymentEventsProvider, (_, __) {});
    final lastPayment = ref.watch(paymentEventsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(liveMetricsProvider),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RevenueCard(
            revenueChf: metrics.todayRevenueChf,
            pulseKey: lastPayment.maybeWhen(
              data: (p) => p.at.millisecondsSinceEpoch,
              orElse: () => 0,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _KpiTile(
                  label: 'Açık masa',
                  value: '${metrics.openTableCount}',
                  icon: Icons.table_restaurant,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiTile(
                  label: 'Aktif sipariş',
                  value: '${metrics.activeOrderCount}',
                  icon: Icons.receipt_long,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiTile(
                  label: 'Son 15dk kişi',
                  value: '${metrics.last15MinCovers}',
                  icon: Icons.people,
                  color: AppColors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _TopProductsCard(items: metrics.top5),
          const SizedBox(height: 16),
          _AsOfFooter(asOf: metrics.asOf),
        ],
      ),
    );
  }
}

class _RevenueCard extends StatefulWidget {
  final double revenueChf;
  final int pulseKey;
  const _RevenueCard({required this.revenueChf, required this.pulseKey});

  @override
  State<_RevenueCard> createState() => _RevenueCardState();
}

class _RevenueCardState extends State<_RevenueCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _lastPulseKey = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      lowerBound: 0,
      upperBound: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _RevenueCard old) {
    super.didUpdateWidget(old);
    if (widget.pulseKey != 0 && widget.pulseKey != _lastPulseKey) {
      _lastPulseKey = widget.pulseKey;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
      locale: 'de_CH',
      symbol: 'CHF ',
      decimalDigits: 0,
    );
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final glow = (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
        return Container(
          key: const Key('boss-revenue-card'),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Color.lerp(
                AppColors.border,
                AppColors.accent,
                glow,
              )!,
              width: 1 + glow,
            ),
            boxShadow: glow > 0
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.25 * glow),
                      blurRadius: 24 * glow,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.payments_outlined,
                      color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Bugün',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                fmt.format(widget.revenueChf),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Canlı — yeni ödemelerle güncellenir',
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopProductsCard extends StatelessWidget {
  final List<TopProduct> items;
  const _TopProductsCard({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxQty = items
        .map((e) => e.quantity)
        .fold<int>(0, (a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'En çok satan 5',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxQty * 1.2).ceilToDouble(),
                barGroups: [
                  for (var i = 0; i < items.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: items[i].quantity.toDouble(),
                          color: AppColors.accent,
                          width: 18,
                          borderRadius:
                              const BorderRadius.all(Radius.circular(4)),
                        ),
                      ],
                    ),
                ],
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= items.length) {
                          return const SizedBox.shrink();
                        }
                        final name = items[idx].name;
                        final short = name.length > 8
                            ? '${name.substring(0, 7)}…'
                            : name;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            short,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final p in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    '× ${p.quantity}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AsOfFooter extends StatelessWidget {
  final DateTime asOf;
  const _AsOfFooter({required this.asOf});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.Hms();
    return Center(
      child: Text(
        'Son güncelleme: ${fmt.format(asOf)}',
        style: const TextStyle(color: AppColors.textDim, fontSize: 11),
      ),
    );
  }
}
