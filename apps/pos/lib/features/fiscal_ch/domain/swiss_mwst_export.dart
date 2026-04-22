/// Swiss MWST export service.
///
/// Produces a per-period fiscal snapshot that Swiss accounting software
/// (Abacus, Bexio, Sage) can ingest directly:
///   * CSV — human-readable, BOM-prefixed for Excel, with a machine
///     block between `#SUMMARY_START` / `#SUMMARY_END`.
///   * JSON — fully structured, includes per-rate buckets, payment
///     split, hourly breakdown, and report window.
///
/// The service is pure — it takes a [ReportSnapshot] (already aggregated
/// by `ReportsRepository.generateSnapshot`) and emits strings. Callers
/// persist the files and drive the OS share sheet.
library;

import 'dart:convert';

import 'package:gastrocore_pos/features/reports/domain/entities/report_entities.dart';

/// Metadata for a Swiss fiscal export — displayed in the CSV header and
/// embedded in the JSON envelope so the downstream consumer knows which
/// tenant / VAT number the file belongs to.
class SwissFiscalMeta {
  const SwissFiscalMeta({
    required this.restaurantName,
    required this.mwstNumber,
    required this.tenantId,
    this.address,
  });

  final String restaurantName;

  /// Swiss VAT registration number in the canonical `CHE-XXX.XXX.XXX MWST`
  /// form. Empty string is accepted (pre-registration trials) and
  /// rendered as "—" in outputs.
  final String mwstNumber;

  final String tenantId;

  /// Optional postal address line (e.g. "Bahnhofstrasse 1, 8001 Zürich").
  final String? address;
}

/// Result bundle returned by [SwissMwstExportService.export].
class SwissMwstExport {
  const SwissMwstExport({
    required this.csv,
    required this.json,
    required this.filenameBase,
  });

  /// UTF-8 (with BOM) CSV string.
  final String csv;

  /// Pretty-printed JSON string.
  final String json;

  /// Filename stem (without extension), e.g.
  /// `mwst-export_2026-04-22_2026-04-22`. The caller appends `.csv`
  /// and `.json`.
  final String filenameBase;
}

/// Pure CSV + JSON generator for Swiss MWST fiscal exports.
///
/// Consumes a [ReportSnapshot] built by `ReportsRepository` and a
/// [SwissFiscalMeta] identifying the tenant. Returns a [SwissMwstExport]
/// with both payloads ready to persist.
class SwissMwstExportService {
  const SwissMwstExportService();

  SwissMwstExport export({
    required ReportSnapshot snapshot,
    required SwissFiscalMeta meta,
    DateTime? generatedAt,
  }) {
    final when = generatedAt ?? DateTime.now();
    final csv = _buildCsv(snapshot, meta, when);
    final json = _buildJson(snapshot, meta, when);
    final base = _filenameBase(snapshot);
    return SwissMwstExport(csv: csv, json: json, filenameBase: base);
  }

  // --------------------------------------------------------------------------
  // CSV
  // --------------------------------------------------------------------------

  String _buildCsv(
    ReportSnapshot s,
    SwissFiscalMeta meta,
    DateTime generatedAt,
  ) {
    final buf = StringBuffer();

    buf.write('\uFEFF'); // UTF-8 BOM for Excel
    buf.writeln('# MWST-Auswertung');
    buf.writeln('# Betrieb: ${_csv(meta.restaurantName)}');
    buf.writeln('# MWST-Nr: ${_csv(meta.mwstNumber.isEmpty ? '—' : meta.mwstNumber)}');
    if (meta.address != null && meta.address!.trim().isNotEmpty) {
      buf.writeln('# Adresse: ${_csv(meta.address!)}');
    }
    buf.writeln('# Tenant: ${_csv(meta.tenantId)}');
    buf.writeln('# Zeitraum: ${_fmtDateTime(s.fromTs)} - ${_fmtDateTime(s.toTs)}');
    buf.writeln('# Erstellt: ${_fmtDateTime(generatedAt)}');
    buf.writeln('#');

    buf.writeln('MwSt-Satz-%,Brutto_CHF,Netto_CHF,MwSt_CHF');
    for (final b in _sortedBuckets(s.mwstBuckets)) {
      buf.writeln([
        _fmtRate(b.ratePercent),
        _fmtChf(b.grossCents),
        _fmtChf(b.netCents),
        _fmtChf(b.taxCents),
      ].join(','));
    }

    final grossTotal = s.mwstBuckets.fold(0, (a, b) => a + b.grossCents);
    final netTotal = s.mwstBuckets.fold(0, (a, b) => a + b.netCents);
    final taxTotal = s.mwstBuckets.fold(0, (a, b) => a + b.taxCents);

    buf.writeln('#');
    buf.writeln('# ZAHLUNGSARTEN');
    buf.writeln('Methode,Anzahl,Summe_CHF');
    for (final p in s.payments) {
      buf.writeln([
        _csv(p.method),
        p.count.toString(),
        _fmtChf(p.totalCents),
      ].join(','));
    }

    buf.writeln('#');
    buf.writeln(
      '# TOTAL | ${s.ticketCount} Belege | Brutto: CHF '
      '${_fmtChf(grossTotal)} | MwSt: CHF ${_fmtChf(taxTotal)} | Netto: '
      'CHF ${_fmtChf(netTotal)}',
    );
    buf.writeln(
      '# Trinkgeld: CHF ${_fmtChf(s.tipTotalCents)} | Rabatt: CHF '
      '${_fmtChf(s.discountTotalCents)} | Storno: ${s.voidCount}',
    );

    // Machine-readable block for accounting software ingest.
    buf.writeln('#SUMMARY_START');
    for (final b in _sortedBuckets(s.mwstBuckets)) {
      buf.writeln(
        'SUMMARY,${_fmtRate(b.ratePercent)},'
        '${_fmtChf(b.grossCents)},${_fmtChf(b.netCents)},'
        '${_fmtChf(b.taxCents)}',
      );
    }
    buf.writeln(
      'TOTAL,,${_fmtChf(grossTotal)},${_fmtChf(netTotal)},${_fmtChf(taxTotal)}',
    );
    buf.writeln('#SUMMARY_END');

    return buf.toString();
  }

  // --------------------------------------------------------------------------
  // JSON
  // --------------------------------------------------------------------------

  String _buildJson(
    ReportSnapshot s,
    SwissFiscalMeta meta,
    DateTime generatedAt,
  ) {
    final envelope = <String, dynamic>{
      'schema': 'ch.mwst.export.v1',
      'generatedAt': generatedAt.toIso8601String(),
      'meta': <String, dynamic>{
        'tenantId': meta.tenantId,
        'restaurantName': meta.restaurantName,
        'mwstNumber': meta.mwstNumber,
        if (meta.address != null) 'address': meta.address,
      },
      'window': <String, dynamic>{
        'from': s.fromTs.toIso8601String(),
        'to': s.toTs.toIso8601String(),
      },
      'totals': <String, dynamic>{
        'ticketCount': s.ticketCount,
        'voidCount': s.voidCount,
        'grossCents': s.grossTotalCents,
        'netCents': s.netTotalCents,
        'taxCents': s.taxTotalCents,
        'tipCents': s.tipTotalCents,
        'discountCents': s.discountTotalCents,
        'giftCents': s.giftTotalCents,
      },
      'mwstBuckets': _sortedBuckets(s.mwstBuckets)
          .map((b) => b.toJson())
          .toList(growable: false),
      'payments':
          s.payments.map((p) => p.toJson()).toList(growable: false),
      'hourly': s.hourly.map((h) => h.toJson()).toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  List<MwstBucket> _sortedBuckets(List<MwstBucket> buckets) {
    final sorted = List<MwstBucket>.from(buckets)
      ..sort((a, b) => a.rateBps.compareTo(b.rateBps));
    return sorted;
  }

  String _filenameBase(ReportSnapshot s) {
    final from = _fmtDate(s.fromTs);
    final to = _fmtDate(s.toTs.subtract(const Duration(seconds: 1)));
    return from == to
        ? 'mwst-export_$from'
        : 'mwst-export_${from}_$to';
  }

  String _fmtDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  String _fmtDateTime(DateTime dt) =>
      '${_fmtDate(dt)} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  String _fmtRate(double rate) => rate.toStringAsFixed(2);

  String _fmtChf(int cents) {
    final isNeg = cents < 0;
    final abs = cents.abs();
    return '${isNeg ? '-' : ''}${abs ~/ 100}.'
        '${(abs % 100).toString().padLeft(2, '0')}';
  }

  String _csv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
