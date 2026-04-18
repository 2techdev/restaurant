/// Z-report screen — pick a date, see end-of-day rollup.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';
import 'package:intl/intl.dart';

import 'zreport_models.dart';
import 'zreport_providers.dart';

class ZReportScreen extends ConsumerWidget {
  const ZReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final report = ref.watch(zReportProvider);

    return Column(
      children: [
        _DatePickerHeader(date: date),
        Expanded(
          child: report.when(
            data: (z) => _ZReportBody(report: z),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => GastrocoreErrorWidget(
              message: 'Z-Rapor yüklenemedi: $e',
              onRetry: () => ref.invalidate(zReportProvider),
            ),
          ),
        ),
      ],
    );
  }
}

class _DatePickerHeader extends ConsumerWidget {
  final DateTime date;
  const _DatePickerHeader({required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('dd MMMM yyyy', 'tr');
    return Material(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            IconButton(
              key: const Key('zreport-prev-day'),
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _shift(ref, -1),
            ),
            Expanded(
              child: TextButton.icon(
                key: const Key('zreport-pick-date'),
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(
                  fmt.format(date),
                  style: const TextStyle(fontSize: 15),
                ),
                onPressed: () => _pickDate(context, ref),
              ),
            ),
            IconButton(
              key: const Key('zreport-next-day'),
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _shift(ref, 1),
            ),
          ],
        ),
      ),
    );
  }

  void _shift(WidgetRef ref, int delta) {
    final cur = ref.read(selectedDateProvider);
    ref.read(selectedDateProvider.notifier).state =
        cur.add(Duration(days: delta));
  }

  Future<void> _pickDate(BuildContext context, WidgetRef ref) async {
    final cur = ref.read(selectedDateProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      ref.read(selectedDateProvider.notifier).state = picked;
    }
  }
}

class _ZReportBody extends StatelessWidget {
  final ZReport report;
  const _ZReportBody({required this.report});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'de_CH',
      symbol: 'CHF ',
      decimalDigits: 2,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryCard(report: report, money: money),
        const SizedBox(height: 16),
        _SectionTitle('MWST (KDV)'),
        const SizedBox(height: 8),
        _VatTable(buckets: report.vatBuckets, money: money),
        const SizedBox(height: 16),
        _SectionTitle('Ödeme yöntemi'),
        const SizedBox(height: 8),
        _PaymentTable(buckets: report.paymentBuckets, money: money),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final ZReport report;
  final NumberFormat money;
  const _SummaryCard({required this.report, required this.money});

  @override
  Widget build(BuildContext context) {
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
            'Günlük özet',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            money.format(report.grossSalesChf),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _Row(label: 'Net satış', value: money.format(report.netSalesChf)),
          _Row(label: 'KDV toplam', value: money.format(report.totalTaxChf)),
          _Row(
            label: 'İskonto',
            value: '-${money.format(report.discountTotalChf)}',
            valueColor: AppColors.orange,
          ),
          _Row(
            label: 'Servis bedeli',
            value: money.format(report.serviceChargeChf),
            valueColor: AppColors.green,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _Row({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _VatTable extends StatelessWidget {
  final List<VatBucket> buckets;
  final NumberFormat money;
  const _VatTable({required this.buckets, required this.money});

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return const _Empty(message: 'KDV bucket yok');
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const _TableHeader(cells: ['Oran', 'Net', 'Vergi', 'Brüt']),
          for (final b in buckets)
            _TableRow(cells: [
              '%${b.ratePercent.toStringAsFixed(b.ratePercent == 0 ? 0 : 1)}',
              money.format(b.netChf),
              money.format(b.taxChf),
              money.format(b.grossChf),
            ]),
        ],
      ),
    );
  }
}

class _PaymentTable extends StatelessWidget {
  final List<PaymentBucket> buckets;
  final NumberFormat money;
  const _PaymentTable({required this.buckets, required this.money});

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return const _Empty(message: 'Ödeme bucket yok');
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const _TableHeader(cells: ['Yöntem', 'Adet', 'Tutar']),
          for (final b in buckets)
            _TableRow(cells: [
              _localizeMethod(b.method),
              '${b.count}',
              money.format(b.amountChf),
            ]),
        ],
      ),
    );
  }

  static String _localizeMethod(String method) {
    switch (method) {
      case 'cash':
        return 'Nakit';
      case 'card':
        return 'Kart';
      case 'twint':
        return 'TWINT';
      case 'voucher':
        return 'Kupon';
      default:
        return method;
    }
  }
}

class _TableHeader extends StatelessWidget {
  final List<String> cells;
  const _TableHeader({required this.cells});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: cells
            .map((c) => Expanded(
                  child: Text(
                    c,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final List<String> cells;
  const _TableRow({required this.cells});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: cells
            .map((c) => Expanded(
                  child: Text(
                    c,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String message;
  const _Empty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textDim, fontSize: 12),
      ),
    );
  }
}
