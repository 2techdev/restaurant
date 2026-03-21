/// MWST CSV Export Service.
///
/// Generates a Swiss-tax-compliant CSV file that groups all transactions
/// for a given date range by VAT rate (MwSt-Code A / B / C).
///
/// CSV columns:
///   Datum, Beleg-Nr, Tisch, Kassier, Betrag_CHF, MwSt_Code, MwSt_Satz_%,
///   Netto_CHF, MwSt_CHF, Brutto_CHF
///
/// Footer rows (starting with '#') contain per-rate and grand totals —
/// these are importable by Swiss accounting software (e.g. Abacus, Bexio).
library;

import 'package:gastrocore_pos/core/printing/models/print_models.dart';

// ---------------------------------------------------------------------------
// Input models
// ---------------------------------------------------------------------------

/// A single transaction line fed into the CSV export.
class MwstTransactionLine {
  const MwstTransactionLine({
    required this.date,
    required this.receiptNo,
    this.tableName,
    this.cashierName,
    required this.grossAmountCents,
    required this.mwstCode,
  });

  final DateTime date;
  final String receiptNo;
  final String? tableName;
  final String? cashierName;

  /// Transaction total including MWST (Brutto), in cents.
  final int grossAmountCents;

  final MwStCode mwstCode;

  /// Calculated MWST amount (Brutto × rate / (100 + rate)), rounded.
  int get taxAmountCents =>
      (grossAmountCents * mwstCode.rate / (100 + mwstCode.rate)).round();

  /// Net amount (Netto = Brutto − MwSt), in cents.
  int get netAmountCents => grossAmountCents - taxAmountCents;
}

// ---------------------------------------------------------------------------
// Summary per rate
// ---------------------------------------------------------------------------

/// Aggregated totals for one MwSt rate bucket.
class MwstRateSummary {
  const MwstRateSummary({
    required this.code,
    required this.transactionCount,
    required this.grossTotalCents,
    required this.taxTotalCents,
    required this.netTotalCents,
  });

  final MwStCode code;
  final int transactionCount;
  final int grossTotalCents;
  final int taxTotalCents;
  final int netTotalCents;
}

// ---------------------------------------------------------------------------
// Export result
// ---------------------------------------------------------------------------

/// Result of [MwstCsvExportService.exportDaily].
class MwstCsvExport {
  const MwstCsvExport({
    required this.csv,
    required this.rateSummaries,
    required this.grandTotalGrossCents,
    required this.grandTotalTaxCents,
    required this.grandTotalNetCents,
  });

  /// Complete CSV string (UTF-8, BOM-prefixed for Excel compatibility).
  final String csv;

  /// Per-rate aggregated totals.
  final List<MwstRateSummary> rateSummaries;

  final int grandTotalGrossCents;
  final int grandTotalTaxCents;
  final int grandTotalNetCents;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Generates a daily MWST CSV export from a list of transactions.
///
/// Usage:
/// ```dart
/// final service = MwstCsvExportService();
/// final result = service.exportDaily(
///   date: DateTime(2024, 3, 15),
///   restaurantName: 'Restaurant Zum Löwen',
///   mwstNr: 'CHE-123.456.789 MWST',
///   transactions: [...],
/// );
/// // Write result.csv to a file or share it.
/// ```
class MwstCsvExportService {
  const MwstCsvExportService();

  /// Generate the daily MWST CSV export.
  ///
  /// [date]            — the business day being exported
  /// [restaurantName]  — printed in the file header
  /// [mwstNr]          — Swiss VAT number shown in header (CHE-XXX.XXX.XXX MWST)
  /// [transactions]    — all transactions for the day
  MwstCsvExport exportDaily({
    required DateTime date,
    required String restaurantName,
    required String mwstNr,
    required List<MwstTransactionLine> transactions,
  }) {
    final buf = StringBuffer();
    final dateStr = _fmtDate(date);

    // BOM + header comment
    buf.write('\uFEFF'); // UTF-8 BOM for Excel
    buf.writeln('# MWST-Tagesabrechnung');
    buf.writeln('# Betrieb: ${_csvEscape(restaurantName)}');
    buf.writeln('# MWST-Nr: ${_csvEscape(mwstNr.isEmpty ? "—" : mwstNr)}');
    buf.writeln('# Datum: $dateStr');
    buf.writeln('# Erstellt: ${_fmtDateTime(DateTime.now())}');
    buf.writeln('#');

    // Column headers
    buf.writeln(
      'Datum,Beleg-Nr,Tisch,Kassier,MwSt-Code,MwSt-Satz-%,'
      'Brutto_CHF,MwSt_CHF,Netto_CHF',
    );

    // Data rows — sorted by date then receipt number
    final sorted = List<MwstTransactionLine>.from(transactions)
      ..sort((a, b) {
        final cmp = a.date.compareTo(b.date);
        return cmp != 0 ? cmp : a.receiptNo.compareTo(b.receiptNo);
      });

    for (final tx in sorted) {
      buf.writeln([
        _fmtDate(tx.date),
        _csvEscape(tx.receiptNo),
        _csvEscape(tx.tableName ?? '—'),
        _csvEscape(tx.cashierName ?? '—'),
        tx.mwstCode.code,
        _fmtRate(tx.mwstCode.rate),
        _fmtChf(tx.grossAmountCents),
        _fmtChf(tx.taxAmountCents),
        _fmtChf(tx.netAmountCents),
      ].join(','));
    }

    // Per-rate subtotals
    buf.writeln('#');
    buf.writeln('# ZUSAMMENFASSUNG NACH MWST-SATZ');

    final summaries = _computeSummaries(transactions);

    for (final s in summaries) {
      buf.writeln([
        '# Cod ${s.code.code} (${_fmtRate(s.code.rate)}%)',
        '${s.transactionCount} Belege',
        'Brutto: CHF ${_fmtChf(s.grossTotalCents)}',
        'MwSt: CHF ${_fmtChf(s.taxTotalCents)}',
        'Netto: CHF ${_fmtChf(s.netTotalCents)}',
      ].join(' | '));
    }

    // Grand total
    final grandGross = summaries.fold(0, (s, e) => s + e.grossTotalCents);
    final grandTax = summaries.fold(0, (s, e) => s + e.taxTotalCents);
    final grandNet = summaries.fold(0, (s, e) => s + e.netTotalCents);

    buf.writeln('#');
    buf.writeln(
      '# TOTAL | ${transactions.length} Belege'
      ' | Brutto: CHF ${_fmtChf(grandGross)}'
      ' | MwSt: CHF ${_fmtChf(grandTax)}'
      ' | Netto: CHF ${_fmtChf(grandNet)}',
    );

    // Machine-readable summary rows for accounting import
    buf.writeln('#SUMMARY_START');
    for (final s in summaries) {
      buf.writeln(
        'SUMMARY,${s.code.code},${_fmtRate(s.code.rate)}'
        ',${_fmtChf(s.grossTotalCents)}'
        ',${_fmtChf(s.taxTotalCents)}'
        ',${_fmtChf(s.netTotalCents)}',
      );
    }
    buf.writeln(
      'TOTAL,,,'
      '${_fmtChf(grandGross)}'
      ',${_fmtChf(grandTax)}'
      ',${_fmtChf(grandNet)}',
    );
    buf.writeln('#SUMMARY_END');

    return MwstCsvExport(
      csv: buf.toString(),
      rateSummaries: summaries,
      grandTotalGrossCents: grandGross,
      grandTotalTaxCents: grandTax,
      grandTotalNetCents: grandNet,
    );
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  List<MwstRateSummary> _computeSummaries(
    List<MwstTransactionLine> transactions,
  ) {
    final buckets = <MwStCode, List<MwstTransactionLine>>{};
    for (final tx in transactions) {
      buckets.putIfAbsent(tx.mwstCode, () => []).add(tx);
    }

    final summaries = <MwstRateSummary>[];
    // Emit in canonical order A → B → C
    for (final code in [MwStCode.a, MwStCode.b, MwStCode.c]) {
      final lines = buckets[code] ?? [];
      if (lines.isEmpty) continue;
      summaries.add(MwstRateSummary(
        code: code,
        transactionCount: lines.length,
        grossTotalCents: lines.fold(0, (s, l) => s + l.grossAmountCents),
        taxTotalCents: lines.fold(0, (s, l) => s + l.taxAmountCents),
        netTotalCents: lines.fold(0, (s, l) => s + l.netAmountCents),
      ));
    }
    return summaries;
  }

  String _fmtDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _fmtDateTime(DateTime dt) {
    return '${_fmtDate(dt)} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Format cents as decimal CHF string, e.g. 12345 → "123.45"
  String _fmtChf(int cents) {
    final isNeg = cents < 0;
    final abs = cents.abs();
    return '${isNeg ? '-' : ''}${(abs ~/ 100)}.${(abs % 100).toString().padLeft(2, '0')}';
  }

  /// Format a rate, removing trailing zeros: 8.1 → "8.10", 2.6 → "2.60"
  String _fmtRate(double rate) => rate.toStringAsFixed(2);

  /// Escape a CSV field: wrap in quotes if it contains comma, quote, or newline.
  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
