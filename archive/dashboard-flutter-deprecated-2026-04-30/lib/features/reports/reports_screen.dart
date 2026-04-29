import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/models.dart';
import '../../core/theme/app_theme.dart';
import 'reports_provider.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(reportsTabProvider);
    final theme = Theme.of(context);

    const tabs = ['Umsatz', 'Kategorien', 'Zahlung', 'Personal', 'MWST'];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
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
                    Text('Berichte', style: theme.textTheme.headlineMedium),
                    Text('Umsatz und Statistiken', style: theme.textTheme.bodyMedium),
                  ],
                ),
                const Spacer(),
                const _DateRangePicker(),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('Export'),
                  onPressed: () => _exportReport(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Tabs
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: tabs.asMap().entries.map((e) {
                  final selected = e.key == tab;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: selected,
                      onSelected: (_) => ref.read(reportsTabProvider.notifier).state = e.key,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: switch (tab) {
                0 => const _SalesTab(),
                1 => const _CategoryTab(),
                2 => const _PaymentTab(),
                3 => const _StaffTab(),
                4 => const _MWSTTab(),
                _ => const SizedBox.shrink(),
              },
            ),
          ],
        ),
      ),
    );
  }

  void _exportReport(BuildContext context, WidgetRef ref) {
    final range = ref.read(reportsDateRangeProvider);
    final tab = ref.read(reportsTabProvider);
    const names = ['Umsatz', 'Kategorien', 'Zahlung', 'Personal', 'MWST'];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${names[tab]}-Bericht (${range.from}–${range.to}) wird exportiert…')),
    );
  }
}

// ---------------------------------------------------------------------------
// Date range picker
// ---------------------------------------------------------------------------

class _DateRangePicker extends ConsumerWidget {
  const _DateRangePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportsDateRangeProvider);

    const presets = [
      ('7d', 'Letzte 7T'),
      ('30d', 'Letzte 30T'),
      ('mtd', 'Dieser Monat'),
    ];

    return PopupMenuButton<String>(
      initialValue: null,
      tooltip: 'Zeitraum wählen',
      child: OutlinedButton.icon(
        icon: const Icon(Icons.calendar_today_outlined, size: 14),
        label: Text('${range.from}  –  ${range.to}', style: const TextStyle(fontSize: 12)),
        onPressed: null,
      ),
      itemBuilder: (_) => presets.map((p) {
        return PopupMenuItem(
          value: p.$1,
          child: Text(p.$2),
        );
      }).toList(),
      onSelected: (v) {
        final now = DateTime.now();
        DateRange range;
        switch (v) {
          case '7d':
            range = DateRange(
              from: DateRange.fmt(now.subtract(const Duration(days: 6))),
              to: DateRange.fmt(now),
            );
          case 'mtd':
            range = DateRange.thisMonth;
          default: // 30d
            range = DateRange.lastMonth;
        }
        ref.read(reportsDateRangeProvider.notifier).state = range;
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sales tab
// ---------------------------------------------------------------------------

class _SalesTab extends ConsumerWidget {
  const _SalesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(salesTimelineProvider);
    final theme = Theme.of(context);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (points) {
        final totalRevenue = points.fold(0, (s, p) => s + p.revenue);
        final totalOrders = points.fold(0, (s, p) => s + p.orderCount);
        final avgOrder = totalOrders > 0 ? totalRevenue ~/ totalOrders : 0;

        return Column(
          children: [
            // Summary cards
            Row(children: [
              Expanded(child: _SummaryCard(
                label: 'Gesamtumsatz',
                value: 'CHF ${(totalRevenue / 100).toStringAsFixed(2)}',
                icon: Icons.attach_money,
                color: AppColors.success,
              )),
              const SizedBox(width: 12),
              Expanded(child: _SummaryCard(
                label: 'Bestellungen',
                value: totalOrders.toString(),
                icon: Icons.receipt_long,
                color: AppColors.primary,
              )),
              const SizedBox(width: 12),
              Expanded(child: _SummaryCard(
                label: 'Ø Bon',
                value: 'CHF ${(avgOrder / 100).toStringAsFixed(2)}',
                icon: Icons.shopping_bag_outlined,
                color: AppColors.warning,
              )),
            ]),
            const SizedBox(height: 16),

            // Group by selector
            Align(
              alignment: Alignment.centerLeft,
              child: _GroupByChips(),
            ),
            const SizedBox(height: 12),

            // Bar chart
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Umsatzverlauf', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 16),
                      Expanded(
                        child: points.isEmpty
                            ? const Center(child: Text('Keine Daten'))
                            : _SalesBarChart(points: points),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GroupByChips extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(reportsGroupByProvider);
    const options = [('day', 'Täglich'), ('week', 'Wöchentlich'), ('month', 'Monatlich')];
    return Row(
      children: options.map((o) {
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: ChoiceChip(
            label: Text(o.$2),
            selected: current == o.$1,
            onSelected: (_) => ref.read(reportsGroupByProvider.notifier).state = o.$1,
            visualDensity: VisualDensity.compact,
          ),
        );
      }).toList(),
    );
  }
}

class _SalesBarChart extends StatelessWidget {
  final List<SalesPoint> points;

  const _SalesBarChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxY = points.map((p) => p.revenue / 100).reduce((a, b) => a > b ? a : b) * 1.2;
    final labelColor = isDark ? Colors.white60 : Colors.grey.shade600;
    const visible = 12;
    final slice = points.length > visible ? points.sublist(points.length - visible) : points;

    return BarChart(
      BarChartData(
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
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= slice.length) return const SizedBox.shrink();
                final parts = slice[i].period.split('-');
                final label = parts.length >= 2 ? '${parts[2]}.${parts[1]}' : slice[i].period;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label, style: TextStyle(fontSize: 9, color: labelColor)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) => Text(
                'CHF ${value.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 9, color: labelColor),
              ),
            ),
          ),
        ),
        barGroups: slice.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value.revenue / 100,
                color: AppColors.primary,
                width: 16,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }).toList(),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => isDark ? const Color(0xFF374151) : Colors.white,
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              'CHF ${rod.toY.toStringAsFixed(2)}\n${slice[group.x].orderCount} Bestellungen',
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category tab
// ---------------------------------------------------------------------------

class _CategoryTab extends ConsumerWidget {
  const _CategoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-use sales data but show category breakdown (demo data)
    const cats = [
      _CatData('Hauptspeisen', 148500, 0xFF4F46E5),
      _CatData('Getränke', 87200, 0xFF10B981),
      _CatData('Vorspeisen', 43100, 0xFFF59E0B),
      _CatData('Desserts', 21800, 0xFFEC4899),
    ];
    final total = cats.fold(0, (s, c) => s + c.revenue);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth > 600;
          final chart = SizedBox(
            width: 200,
            height: 200,
            child: PieChart(
              PieChartData(
                sections: cats.map((c) {
                  final pct = total > 0 ? c.revenue / total * 100 : 0.0;
                  return PieChartSectionData(
                    color: Color(c.colorValue),
                    value: pct,
                    title: '${pct.toStringAsFixed(0)}%',
                    radius: 70,
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
                sectionsSpace: 2,
                centerSpaceRadius: 0,
              ),
            ),
          );
          final legend = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: cats.map((c) {
              final pct = total > 0 ? c.revenue / total * 100 : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Color(c.colorValue),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(c.name, style: theme.textTheme.bodyLarge)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'CHF ${(c.revenue / 100).toStringAsFixed(2)}',
                          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text('${pct.toStringAsFixed(1)}%', style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          );

          if (wide) {
            return Row(
              children: [
                chart,
                const SizedBox(width: 40),
                Expanded(child: legend),
              ],
            );
          }
          return Column(children: [chart, const SizedBox(height: 24), legend]);
        }),
      ),
    );
  }
}

class _CatData {
  final String name;
  final int revenue;
  final int colorValue;

  const _CatData(this.name, this.revenue, this.colorValue);
}

// ---------------------------------------------------------------------------
// Payment tab
// ---------------------------------------------------------------------------

class _PaymentTab extends ConsumerWidget {
  const _PaymentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const methods = [
      _PayData('Karte', 224300, Icons.credit_card, 0xFF4F46E5),
      _PayData('Twint', 98500, Icons.phone_android, 0xFF10B981),
      _PayData('Bar', 47200, Icons.payments_outlined, 0xFFF59E0B),
      _PayData('Andere', 18700, Icons.more_horiz, 0xFF6B7280),
    ];
    final theme = Theme.of(context);

    return Card(
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: methods.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('Zahlungsmethoden', style: theme.textTheme.titleLarge),
            );
          }
          final m = methods[i - 1];
          final total = methods.fold(0, (s, pm) => s + pm.total);
          final pct = total > 0 ? m.total / total * 100 : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(m.colorValue).withAlpha(26),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(m.icon, color: Color(m.colorValue), size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct / 100,
                          minHeight: 6,
                          backgroundColor: theme.colorScheme.outline.withAlpha(51),
                          valueColor: AlwaysStoppedAnimation(Color(m.colorValue)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'CHF ${(m.total / 100).toStringAsFixed(2)}',
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text('${pct.toStringAsFixed(1)}%', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PayData {
  final String name;
  final int total;
  final IconData icon;
  final int colorValue;

  const _PayData(this.name, this.total, this.icon, this.colorValue);
}

// ---------------------------------------------------------------------------
// Staff tab
// ---------------------------------------------------------------------------

class _StaffTab extends ConsumerWidget {
  const _StaffTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const staff = [
      _StaffData('Maria Müller', 142, 284300),
      _StaffData('Tom Huber', 118, 231500),
      _StaffData('Sara Keller', 97, 189200),
      _StaffData('Jan Schmid', 84, 167400),
    ];
    final theme = Theme.of(context);

    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text('Personalleistung', style: theme.textTheme.titleLarge),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_download_outlined, size: 14),
                  label: const Text('CSV'),
                  onPressed: () {
                    final sb = StringBuffer('Name,Bestellungen,Umsatz CHF\n');
                    for (final s in staff) {
                      sb.writeln('${s.name},${s.orders},${(s.revenue / 100).toStringAsFixed(2)}');
                    }
                    Clipboard.setData(ClipboardData(text: sb.toString()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('In Zwischenablage kopiert')),
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              child: DataTable(
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('Kellner')),
                  DataColumn(label: Text('Bestellungen'), numeric: true),
                  DataColumn(label: Text('Umsatz'), numeric: true),
                  DataColumn(label: Text('Ø Bon'), numeric: true),
                ],
                rows: staff.map((s) {
                  final avg = s.orders > 0 ? s.revenue ~/ s.orders : 0;
                  return DataRow(cells: [
                    DataCell(Row(children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.primary.withAlpha(26),
                        child: Text(
                          s.name[0],
                          style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(s.name),
                    ])),
                    DataCell(Text(s.orders.toString())),
                    DataCell(Text('CHF ${(s.revenue / 100).toStringAsFixed(2)}')),
                    DataCell(Text('CHF ${(avg / 100).toStringAsFixed(2)}')),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffData {
  final String name;
  final int orders;
  final int revenue;

  const _StaffData(this.name, this.orders, this.revenue);
}

// ---------------------------------------------------------------------------
// MWST tab
// ---------------------------------------------------------------------------

class _MWSTTab extends ConsumerWidget {
  const _MWSTTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mwstReportProvider);
    final theme = Theme.of(context);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (report) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('MWST-Abrechnung', style: theme.textTheme.titleLarge),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(26),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${report.from} – ${report.to}',
                      style: const TextStyle(fontSize: 11, color: AppColors.primary),
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.file_download_outlined, size: 14),
                    label: const Text('CSV'),
                    onPressed: () => _exportMWST(context, report),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Table
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    // Header
                    _MWSTRow(
                      isHeader: true,
                      cells: ['Steuergruppe', 'Satz', 'Brutto', 'Netto', 'Steuer'],
                    ),
                    const Divider(height: 1),
                    // Rows
                    ...report.lines.map((l) => Column(children: [
                          _MWSTRow(cells: [
                            _taxGroupLabel(l.taxGroup),
                            '${(l.rate * 100).toStringAsFixed(1)}%',
                            'CHF ${(l.grossAmount / 100).toStringAsFixed(2)}',
                            'CHF ${(l.netAmount / 100).toStringAsFixed(2)}',
                            'CHF ${(l.taxAmount / 100).toStringAsFixed(2)}',
                          ]),
                          const Divider(height: 1),
                        ])),
                    // Total
                    _MWSTRow(
                      isTotal: true,
                      cells: [
                        'Total',
                        '',
                        'CHF ${(report.totalGross / 100).toStringAsFixed(2)}',
                        'CHF ${(report.totalNet / 100).toStringAsFixed(2)}',
                        'CHF ${(report.totalTax / 100).toStringAsFixed(2)}',
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              Text(
                'Alle Beträge in CHF inkl. Rundung. Massgebend ist die MWST-Abrechnung Ihres Treuhänders.',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _exportMWST(BuildContext context, MWSTReport report) {
    final sb = StringBuffer('Steuergruppe,Satz,Brutto CHF,Netto CHF,Steuer CHF\n');
    for (final l in report.lines) {
      sb.writeln([
        _taxGroupLabel(l.taxGroup),
        '${(l.rate * 100).toStringAsFixed(1)}%',
        (l.grossAmount / 100).toStringAsFixed(2),
        (l.netAmount / 100).toStringAsFixed(2),
        (l.taxAmount / 100).toStringAsFixed(2),
      ].join(','));
    }
    sb.writeln(['Total', '',
      (report.totalGross / 100).toStringAsFixed(2),
      (report.totalNet / 100).toStringAsFixed(2),
      (report.totalTax / 100).toStringAsFixed(2),
    ].join(','));
    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('MWST-Tabelle in Zwischenablage kopiert')),
    );
  }
}

class _MWSTRow extends StatelessWidget {
  final List<String> cells;
  final bool isHeader;
  final bool isTotal;

  const _MWSTRow({required this.cells, this.isHeader = false, this.isTotal = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isHeader
        ? theme.colorScheme.surface
        : isTotal
            ? AppColors.primary.withAlpha(13)
            : Colors.transparent;
    final style = isHeader || isTotal
        ? theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)
        : theme.textTheme.bodyLarge;

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(cells[0], style: style)),
          Expanded(child: Text(cells[1], style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(cells[2], style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(cells[3], style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(cells[4], style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

String _taxGroupLabel(String group) => switch (group) {
      'standard' => 'Standard (8.1%)',
      'reduced' => 'Reduziert (3.8%)',
      'accommodation' => 'Beherbergung (2.6%)',
      'exempt' => 'Steuerbefreit (0%)',
      _ => group,
    };

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withAlpha(26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(label, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
