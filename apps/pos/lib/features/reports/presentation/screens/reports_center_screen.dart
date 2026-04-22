/// Reports Center — sealed Z / monthly / period reports with PDF export.
///
/// Three tabs share one [ReportSnapshot] widget tree. The Z tab pins the
/// window to "today 00:00 -> 24:00" and exposes the Seal button; the
/// monthly tab pins to the current month; the period tab lets the
/// operator pick an arbitrary range. A side panel lists previously
/// sealed Z reports with their sequence numbers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/features/fiscal_ch/presentation/swiss_mwst_export_button.dart';
import 'package:gastrocore_pos/features/reports/domain/entities/report_entities.dart';
import 'package:gastrocore_pos/features/reports/presentation/providers/reports_provider.dart';
import 'package:gastrocore_pos/features/reports/services/reports_pdf_exporter.dart';

class ReportsCenterScreen extends ConsumerStatefulWidget {
  const ReportsCenterScreen({super.key});

  @override
  ConsumerState<ReportsCenterScreen> createState() =>
      _ReportsCenterScreenState();
}

class _ReportsCenterScreenState extends ConsumerState<ReportsCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  late DateTime _periodFrom;
  late DateTime _periodTo;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final now = DateTime.now();
    _periodFrom = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 7));
    _periodTo = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  ReportWindow get _today {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return ReportWindow(
      from: start,
      to: start.add(const Duration(days: 1)),
    );
  }

  ReportWindow get _thisMonth {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    return ReportWindow(from: start, to: end);
  }

  ReportWindow get _period => ReportWindow(from: _periodFrom, to: _periodTo);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: const Text('Raporlar / Z-Rapport'),
        backgroundColor: AppColors.surfaceContainerLow,
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Z Raporu'),
            Tab(text: 'Aylık'),
            Tab(text: 'Dönem'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ZTab(window: _today),
          _SnapshotTab(window: _thisMonth, title: 'Aylık Rapor'),
          _PeriodTab(
            window: _period,
            onPick: (range) {
              setState(() {
                _periodFrom = range.start;
                _periodTo = DateTime(
                    range.end.year, range.end.month, range.end.day, 23, 59, 59);
              });
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Z tab — today's window + seal action + previous seals list
// ---------------------------------------------------------------------------

class _ZTab extends ConsumerWidget {
  const _ZTab({required this.window});

  final ReportWindow window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportSnapshotProvider(window));

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: async.when(
            loading: () =>
                const Center(child: CircularProgressIndicator.adaptive()),
            error: (e, _) => _ErrorView(message: e.toString()),
            data: (snapshot) => _ZBody(snapshot: snapshot),
          ),
        ),
        const VerticalDivider(width: 1),
        const SizedBox(
          width: 300,
          child: _SealHistoryPanel(),
        ),
      ],
    );
  }
}

class _ZBody extends ConsumerWidget {
  const _ZBody({required this.snapshot});

  final ReportSnapshot snapshot;

  Future<void> _seal(BuildContext context, WidgetRef ref) async {
    final UserEntity? user = ref.read(currentUserProvider);
    final closedBy = user?.name ?? 'POS';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Z-Rapport mühürle'),
        content: Text(
          'Bu raporu seri numarasıyla mühürlemek üzeresin. '
          'Toplam ${snapshot.ticketCount} bon, '
          '${_chf(snapshot.grossTotalCents)}. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mühürle'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final seal = await ref
        .read(zSealNotifierProvider.notifier)
        .seal(closedBy: closedBy, snapshot: snapshot);

    if (!context.mounted) return;
    if (seal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Z-Rapport mühürlenemedi.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Z #${seal.sequenceNumber.toString().padLeft(4, '0')} mühürlendi.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sealStatus = ref.watch(zSealNotifierProvider);
    final sealing = sealStatus.state == ZSealState.sealing;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Bugünün Z Raporu',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              OutlinedButton.icon(
                onPressed: snapshot.ticketCount == 0
                    ? null
                    : () => ReportsPdfExporter.shareReport(
                          title: 'Z-Rapport',
                          snapshot: snapshot,
                        ),
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('PDF (Önizleme)'),
              ),
              const SizedBox(width: 8),
              SwissMwstExportButton(snapshot: snapshot),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: sealing || snapshot.ticketCount == 0
                    ? null
                    : () => _seal(context, ref),
                icon: sealing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_rounded),
                label: const Text('Z Mühürle'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: _SnapshotBody(snapshot: snapshot)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Monthly tab — pinned to current month
// ---------------------------------------------------------------------------

class _SnapshotTab extends ConsumerWidget {
  const _SnapshotTab({required this.window, required this.title});

  final ReportWindow window;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportSnapshotProvider(window));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (e, _) => _ErrorView(message: e.toString()),
      data: (snapshot) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                OutlinedButton.icon(
                  onPressed: snapshot.ticketCount == 0
                      ? null
                      : () => ReportsPdfExporter.shareReport(
                            title: title,
                            snapshot: snapshot,
                          ),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('PDF'),
                ),
                const SizedBox(width: 8),
                SwissMwstExportButton(snapshot: snapshot),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _SnapshotBody(snapshot: snapshot)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Period tab — operator picks window
// ---------------------------------------------------------------------------

class _PeriodTab extends ConsumerWidget {
  const _PeriodTab({required this.window, required this.onPick});

  final ReportWindow window;
  final void Function(DateTimeRange range) onPick;

  Future<void> _pickRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: window.from,
        end: DateTime(window.to.year, window.to.month, window.to.day),
      ),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportSnapshotProvider(window));
    final df = DateFormat('dd.MM.yyyy');

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (e, _) => _ErrorView(message: e.toString()),
      data: (snapshot) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Dönem Raporu',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickRange(context),
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text(
                      '${df.format(window.from)}  ->  ${df.format(window.to)}'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: snapshot.ticketCount == 0
                      ? null
                      : () => ReportsPdfExporter.shareReport(
                            title: 'Dönem Raporu',
                            snapshot: snapshot,
                          ),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('PDF'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _SnapshotBody(snapshot: snapshot)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared snapshot body — KPI row + sections
// ---------------------------------------------------------------------------

class _SnapshotBody extends StatelessWidget {
  const _SnapshotBody({required this.snapshot});

  final ReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.ticketCount == 0) {
      return const _EmptyState();
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KpiRow(snapshot: snapshot),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'MWST Aufstellung',
            child: _MwstTable(buckets: snapshot.mwstBuckets),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Zahlungsarten',
            child: _PaymentsTable(entries: snapshot.payments,
                tipTotalCents: snapshot.tipTotalCents),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Top 10 Produkte',
            child: _TopProductsTable(products: snapshot.topProducts),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Kategorien',
            child: _CategoriesTable(categories: snapshot.categories),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Stundenverlauf',
            child: _HourlyTable(hourly: snapshot.hourly),
          ),
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.snapshot});

  final ReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final cards = <_KpiCardData>[
      _KpiCardData('Umsatz brutto', _chf(snapshot.grossTotalCents)),
      _KpiCardData('Netto', _chf(snapshot.netTotalCents)),
      _KpiCardData('MWST', _chf(snapshot.taxTotalCents)),
      _KpiCardData('Rabatt', _chf(snapshot.discountTotalCents)),
      _KpiCardData('Trinkgeld', _chf(snapshot.tipTotalCents)),
      _KpiCardData('Geschenk', _chf(snapshot.giftTotalCents)),
      _KpiCardData('Bons', snapshot.ticketCount.toString()),
      _KpiCardData('Storno', snapshot.voidCount.toString()),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards
          .map((c) => SizedBox(
                width: 160,
                child: _KpiCard(data: c),
              ))
          .toList(),
    );
  }
}

class _KpiCardData {
  const _KpiCardData(this.label, this.value);
  final String label;
  final String value;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});
  final _KpiCardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.label,
              style:
                  const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
          const SizedBox(height: 6),
          Text(
            data.value,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _MwstTable extends StatelessWidget {
  const _MwstTable({required this.buckets});
  final List<MwstBucket> buckets;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) return const _EmptyRow();
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        _headerRow(['Satz', 'Brutto', 'Netto', 'MWST']),
        ...buckets.map((b) => _row([
              '${b.ratePercent.toStringAsFixed(1)}%',
              _chf(b.grossCents),
              _chf(b.netCents),
              _chf(b.taxCents),
            ])),
      ],
    );
  }
}

class _PaymentsTable extends StatelessWidget {
  const _PaymentsTable({required this.entries, required this.tipTotalCents});
  final List<PaymentBreakdownEntry> entries;
  final int tipTotalCents;

  static const _labels = <String, String>{
    'cash': 'Bar',
    'credit_card': 'Kreditkarte',
    'debit_card': 'Debitkarte',
    'twint': 'TWINT',
    'other': 'Sonstige',
  };

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const _EmptyRow();
    return Column(
      children: [
        Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            _headerRow(['Methode', 'Anzahl', 'Summe']),
            ...entries.map((e) => _row([
                  _labels[e.method] ?? e.method,
                  e.count.toString(),
                  _chf(e.totalCents),
                ])),
          ],
        ),
        if (tipTotalCents > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Trinkgeld dahil: ${_chf(tipTotalCents)}',
                    style: const TextStyle(
                        fontSize: 12, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
      ],
    );
  }
}

class _TopProductsTable extends StatelessWidget {
  const _TopProductsTable({required this.products});
  final List<TopProductEntry> products;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const _EmptyRow();
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        _headerRow(['Produkt', 'Menge', 'Umsatz']),
        ...products.map((p) => _row([
              p.productName,
              _fmtQty(p.quantity),
              _chf(p.revenueCents),
            ])),
      ],
    );
  }
}

class _CategoriesTable extends StatelessWidget {
  const _CategoriesTable({required this.categories});
  final List<CategoryBreakdownEntry> categories;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const _EmptyRow();
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        _headerRow(['Kategorie', 'Menge', 'Umsatz']),
        ...categories.map((c) => _row([
              c.categoryName,
              _fmtQty(c.quantity),
              _chf(c.revenueCents),
            ])),
      ],
    );
  }
}

class _HourlyTable extends StatelessWidget {
  const _HourlyTable({required this.hourly});
  final List<HourlyBreakdownEntry> hourly;

  @override
  Widget build(BuildContext context) {
    if (hourly.isEmpty) return const _EmptyRow();
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        _headerRow(['Stunde', 'Bons', 'Umsatz']),
        ...hourly.map((h) => _row([
              '${h.hour.toString().padLeft(2, '0')}:00',
              h.ticketCount.toString(),
              _chf(h.revenueCents),
            ])),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Side panel: previously sealed Z reports
// ---------------------------------------------------------------------------

class _SealHistoryPanel extends ConsumerWidget {
  const _SealHistoryPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(zSealHistoryProvider);
    final df = DateFormat('dd.MM.yyyy HH:mm');

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Önceki Z Mühürleri',
              style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Expanded(
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator.adaptive()),
              error: (e, _) => _ErrorView(message: e.toString()),
              data: (seals) {
                if (seals.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Henüz mühürlenmiş Z raporu yok.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF6B7280))),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: seals.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = seals[i];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        child: Text(
                            s.sequenceNumber.toString().padLeft(3, '0'),
                            style: const TextStyle(fontSize: 10)),
                      ),
                      title: Text(
                          'Z #${s.sequenceNumber.toString().padLeft(4, '0')}',
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${df.format(s.closedAt)}\n'
                        '${_chf(s.snapshot.grossTotalCents)} | '
                        '${s.snapshot.ticketCount} bon',
                        style: const TextStyle(fontSize: 12),
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        onPressed: () => ReportsPdfExporter.shareReport(
                          title: 'Z-Rapport',
                          snapshot: s.snapshot,
                          seal: s,
                        ),
                      ),
                    );
                  },
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
// Shared bits
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Color(0xFF94A3B8)),
            SizedBox(height: 12),
            Text('Bu dönem için işlem yok.',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Text('Veri yok.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Text('Hata: $message',
          style: const TextStyle(color: Color(0xFFD54646))),
    );
  }
}

TableRow _headerRow(List<String> cells) => TableRow(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      children: cells
          .map((c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Text(c,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF374151))),
              ))
          .toList(),
    );

TableRow _row(List<String> cells) => TableRow(
      children: cells
          .map((c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                child: Text(c, style: const TextStyle(fontSize: 12)),
              ))
          .toList(),
    );

String _chf(int cents) {
  final isNeg = cents < 0;
  final abs = cents.abs();
  return '${isNeg ? '-' : ''}CHF ${(abs / 100).toStringAsFixed(2)}';
}

String _fmtQty(double v) => v == v.truncateToDouble()
    ? v.toInt().toString()
    : v.toStringAsFixed(2);
