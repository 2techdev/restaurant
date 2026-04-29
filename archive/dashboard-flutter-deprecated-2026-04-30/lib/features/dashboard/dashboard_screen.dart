import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/stat_card.dart';
import 'dashboard_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final revenueAsync = ref.watch(revenueDataProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardStatsProvider);
          ref.invalidate(revenueDataProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dashboard', style: theme.textTheme.headlineMedium),
                      Text(
                        _todayLabel(),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Aktualisieren'),
                    onPressed: () {
                      ref.invalidate(dashboardStatsProvider);
                      ref.invalidate(revenueDataProvider);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Stat cards
              statsAsync.when(
                loading: () => const _StatsLoadingGrid(),
                error: (e, _) => _ErrorCard(message: e.toString()),
                data: (stats) => _StatsGrid(stats: stats),
              ),
              const SizedBox(height: 24),

              // Revenue chart + top items
              LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth > 700;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _RevenueChart(revenueAsync: revenueAsync),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: statsAsync.when(
                          loading: () => const _CardPlaceholder(height: 320),
                          error: (_, __) => const SizedBox.shrink(),
                          data: (stats) => _TopItemsCard(items: stats.topItems),
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    _RevenueChart(revenueAsync: revenueAsync),
                    const SizedBox(height: 16),
                    statsAsync.when(
                      loading: () => const _CardPlaceholder(height: 200),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (stats) => _TopItemsCard(items: stats.topItems),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    const months = [
      '', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
    ];
    return '${now.day}. ${months[now.month]} ${now.year}';
  }
}

// ---------------------------------------------------------------------------
// Stats grid
// ---------------------------------------------------------------------------

class _StatsGrid extends StatelessWidget {
  final DashboardStats stats;

  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatData(
        label: 'Umsatz heute',
        value: _chf(stats.totalRevenue),
        icon: Icons.attach_money,
        iconColor: AppColors.success,
        trend: '+8%',
        trendUp: true,
      ),
      _StatData(
        label: 'Bestellungen',
        value: stats.orderCount.toString(),
        icon: Icons.receipt_long,
        iconColor: AppColors.primary,
        trend: '+3',
        trendUp: true,
      ),
      _StatData(
        label: 'Ø Bon',
        value: _chf(stats.avgTicket),
        icon: Icons.shopping_bag_outlined,
        iconColor: AppColors.warning,
      ),
      _StatData(
        label: 'Aktive Bestellungen',
        value: stats.activeOrders.toString(),
        icon: Icons.pending_outlined,
        iconColor: const Color(0xFF8B5CF6),
      ),
      _StatData(
        label: 'Besetzte Tische',
        value: stats.tablesOccupied.toString(),
        icon: Icons.table_restaurant,
        iconColor: const Color(0xFF06B6D4),
      ),
      _StatData(
        label: 'Personal in Schicht',
        value: stats.staffOnShift.toString(),
        icon: Icons.people_outlined,
        iconColor: const Color(0xFFF97316),
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 900 ? 3 : constraints.maxWidth > 500 ? 2 : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.7,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => StatCard(
          label: items[i].label,
          value: items[i].value,
          icon: items[i].icon,
          iconColor: items[i].iconColor,
          iconBackground: items[i].iconColor.withAlpha(26),
          trend: items[i].trend,
          trendUp: items[i].trendUp,
        ),
      );
    });
  }

  static String _chf(int cents) {
    final fr = cents / 100;
    final parts = fr.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write("'");
      buffer.write(intPart[i]);
    }
    return "CHF ${buffer.toString()}.${parts[1]}";
  }
}

class _StatData {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final String? trend;
  final bool trendUp;

  const _StatData({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.trend,
    this.trendUp = true,
  });
}

class _StatsLoadingGrid extends StatelessWidget {
  const _StatsLoadingGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.7,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => const _CardPlaceholder(height: 110),
    );
  }
}

// ---------------------------------------------------------------------------
// Revenue chart
// ---------------------------------------------------------------------------

class _RevenueChart extends ConsumerWidget {
  final AsyncValue<List<RevenuePoint>> revenueAsync;

  const _RevenueChart({required this.revenueAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final period = ref.watch(revenuePeriodProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Umsatzverlauf', style: theme.textTheme.titleLarge),
                const Spacer(),
                _PeriodChips(current: period),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: revenueAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Fehler: $e')),
                data: (data) => data.isEmpty
                    ? const Center(child: Text('Keine Daten'))
                    : _LineChart(data: data),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodChips extends ConsumerWidget {
  final String current;

  const _PeriodChips({required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const options = [('7d', '7T'), ('30d', '30T'), ('90d', '90T')];
    return Row(
      children: options.map((o) {
        final selected = current == o.$1;
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: ChoiceChip(
            label: Text(o.$2),
            selected: selected,
            onSelected: (_) => ref.read(revenuePeriodProvider.notifier).state = o.$1,
            visualDensity: VisualDensity.compact,
          ),
        );
      }).toList(),
    );
  }
}

class _LineChart extends StatelessWidget {
  final List<RevenuePoint> data;

  const _LineChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spots = data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.revenue / 100))
        .toList();

    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.2;

    final labelColor = isDark ? Colors.white60 : Colors.grey.shade600;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: data.length <= 7 ? 1 : (data.length / 6).roundToDouble(),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                final parts = data[i].date.split('-');
                final label = parts.length == 3 ? '${parts[2]}.${parts[1]}' : '';
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(label, style: TextStyle(fontSize: 10, color: labelColor)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) => Text(
                'CHF ${value.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 9, color: labelColor),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: AppColors.primary,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withAlpha(51),
                  AppColors.primary.withAlpha(0),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => isDark ? const Color(0xFF374151) : Colors.white,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      'CHF ${s.y.toStringAsFixed(2)}',
                      const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top items
// ---------------------------------------------------------------------------

class _TopItemsCard extends StatelessWidget {
  final List<TopItem> items;

  const _TopItemsCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top Artikel heute', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text('Keine Daten', style: theme.textTheme.bodyMedium),
                ),
              )
            else
              ...items.asMap().entries.map((e) => _TopItemRow(
                    rank: e.key + 1,
                    item: e.value,
                    isLast: e.key == items.length - 1,
                  )),
          ],
        ),
      ),
    );
  }
}

class _TopItemRow extends StatelessWidget {
  final int rank;
  final TopItem item;
  final bool isLast;

  const _TopItemRow({required this.rank, required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chf = 'CHF ${(item.revenue / 100).toStringAsFixed(2)}';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: rank == 1
                      ? AppColors.warning.withAlpha(38)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: rank == 1 ? AppColors.warning : theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                    Text('${item.quantity}× verkauft', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              Text(chf, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _CardPlaceholder extends StatelessWidget {
  final double height;

  const _CardPlaceholder({required this.height});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
