/// PDF exporter for the sealed / period reports screen.
///
/// Reuses the `pdf` + `printing` packages already present for the
/// analytics export, but formats Z-report-shaped data: MWST buckets,
/// payment split, top products, category + hourly breakdowns, plus the
/// sealed header (sequence number + closedBy) when a [ZSealEntity] is
/// supplied.
library;

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:gastrocore_pos/features/reports/domain/entities/report_entities.dart';

final _chf = NumberFormat.currency(locale: 'de_CH', symbol: 'CHF ', decimalDigits: 2);
final _dateFmt = DateFormat('dd.MM.yyyy');
final _dateTimeFmt = DateFormat('dd.MM.yyyy HH:mm');

String _fChf(int cents) => _chf.format(cents / 100);

class ReportsPdfExporter {
  ReportsPdfExporter._();

  /// Share / print a Z, monthly, or period report. Pass [seal] to stamp
  /// the PDF header with the sequence number of the sealed row.
  static Future<void> shareReport({
    required String title,
    required ReportSnapshot snapshot,
    ZSealEntity? seal,
  }) async {
    final bytes = await _build(title: title, snapshot: snapshot, seal: seal);
    final filename = seal != null
        ? 'Z-Rapport_${seal.sequenceNumber.toString().padLeft(4, '0')}_'
            '${_dateFmt.format(seal.closedAt)}.pdf'
        : '${title.replaceAll(' ', '_')}_'
            '${_dateFmt.format(snapshot.fromTs)}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  // ---------------------------------------------------------------------------
  // Document
  // ---------------------------------------------------------------------------

  static Future<Uint8List> _build({
    required String title,
    required ReportSnapshot snapshot,
    ZSealEntity? seal,
  }) async {
    final pdf = pw.Document(
      title: 'GastroCore $title',
      author: 'GastroCore POS',
    );

    final theme = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.notoSansRegular(),
      bold: await PdfGoogleFonts.notoSansBold(),
    );

    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
        ),
        build: (ctx) => [
          _header(title, snapshot, seal),
          pw.SizedBox(height: 16),
          _kpiRow(snapshot),
          pw.SizedBox(height: 18),
          _section('MWST Aufstellung'),
          _mwstTable(snapshot),
          pw.SizedBox(height: 14),
          _section('Zahlungsarten'),
          _paymentsTable(snapshot),
          pw.SizedBox(height: 14),
          _section('Top 10 Produkte'),
          _productsTable(snapshot),
          pw.SizedBox(height: 14),
          _section('Kategorien'),
          _categoriesTable(snapshot),
          pw.SizedBox(height: 14),
          _section('Stundenverlauf'),
          _hourlyTable(snapshot),
          pw.SizedBox(height: 14),
          _section('Mitarbeiter'),
          _waiterTable(snapshot),
          if (seal != null) ...[
            pw.SizedBox(height: 18),
            _sealFooter(seal),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  // ---------------------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------------------

  static pw.Widget _header(
    String title,
    ReportSnapshot s,
    ZSealEntity? seal,
  ) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'GastroCore',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                        fontSize: 22, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              if (seal != null)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey900,
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Z-NR.',
                          style: const pw.TextStyle(
                              color: PdfColors.grey300, fontSize: 8)),
                      pw.Text(
                        '#${seal.sequenceNumber.toString().padLeft(4, '0')}',
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Zeitraum: ${_dateTimeFmt.format(s.fromTs)} - '
            '${_dateTimeFmt.format(s.toTs)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.Divider(),
        ],
      );

  static pw.Widget _kpiRow(ReportSnapshot s) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _kpiBox('Umsatz brutto', _fChf(s.grossTotalCents)),
          _kpiBox('Netto', _fChf(s.netTotalCents)),
          _kpiBox('MWST', _fChf(s.taxTotalCents)),
          _kpiBox('Rabatt', _fChf(s.discountTotalCents)),
          _kpiBox('Bons', s.ticketCount.toString()),
          _kpiBox('Storno', s.voidCount.toString()),
        ],
      );

  static pw.Widget _kpiBox(String label, String value) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label,
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey600)),
            pw.SizedBox(height: 2),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  static pw.Widget _section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(
          title,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      );

  static pw.Widget _mwstTable(ReportSnapshot s) {
    if (s.mwstBuckets.isEmpty) return _empty();
    return _table(
      headers: ['Satz', 'Brutto', 'Netto', 'MWST'],
      rows: s.mwstBuckets.map((b) => [
            '${b.ratePercent.toStringAsFixed(1)}%',
            _fChf(b.grossCents),
            _fChf(b.netCents),
            _fChf(b.taxCents),
          ]).toList(),
    );
  }

  static pw.Widget _paymentsTable(ReportSnapshot s) {
    if (s.payments.isEmpty) return _empty();
    final labels = <String, String>{
      'cash': 'Bar',
      'credit_card': 'Kreditkarte',
      'debit_card': 'Debitkarte',
      'twint': 'TWINT',
      'other': 'Sonstige',
    };
    return _table(
      headers: ['Methode', 'Anzahl', 'Summe'],
      rows: s.payments.map((p) => [
            labels[p.method] ?? p.method,
            p.count.toString(),
            _fChf(p.totalCents),
          ]).toList(),
    );
  }

  static pw.Widget _productsTable(ReportSnapshot s) {
    if (s.topProducts.isEmpty) return _empty();
    return _table(
      headers: ['Produkt', 'Menge', 'Umsatz'],
      rows: s.topProducts.map((p) => [
            p.productName,
            _fmtQty(p.quantity),
            _fChf(p.revenueCents),
          ]).toList(),
    );
  }

  static pw.Widget _categoriesTable(ReportSnapshot s) {
    if (s.categories.isEmpty) return _empty();
    return _table(
      headers: ['Kategorie', 'Menge', 'Umsatz'],
      rows: s.categories.map((c) => [
            c.categoryName,
            _fmtQty(c.quantity),
            _fChf(c.revenueCents),
          ]).toList(),
    );
  }

  static pw.Widget _hourlyTable(ReportSnapshot s) {
    if (s.hourly.isEmpty) return _empty();
    return _table(
      headers: ['Stunde', 'Bons', 'Umsatz'],
      rows: s.hourly.map((h) => [
            '${h.hour.toString().padLeft(2, '0')}:00',
            h.ticketCount.toString(),
            _fChf(h.revenueCents),
          ]).toList(),
    );
  }

  static pw.Widget _waiterTable(ReportSnapshot s) {
    if (s.waiters.isEmpty) return _empty();
    return _table(
      headers: ['Mitarbeiter', 'Bons', 'Umsatz', 'Trinkgeld'],
      rows: s.waiters
          .map((w) => [
                w.waiterName,
                w.ticketCount.toString(),
                _fChf(w.revenueCents),
                _fChf(w.tipCents),
              ])
          .toList(),
    );
  }

  static pw.Widget _sealFooter(ZSealEntity seal) => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Versiegelter Z-Bericht',
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Sequenz: ${seal.sequenceNumber} | Abgeschlossen: '
              '${_dateTimeFmt.format(seal.closedAt)} | '
              'Von: ${seal.closedBy}',
              style:
                  const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      );

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _fmtQty(double v) => v == v.truncateToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(2);

  static pw.Widget _empty() => pw.Text(
        'Keine Daten.',
        style: const pw.TextStyle(color: PdfColors.grey500, fontSize: 10),
      );

  static pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    final headerWidgets = headers
        .map((h) => pw.Text(h,
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800)))
        .toList();

    final dataRows = rows
        .map((r) => r
            .map((c) =>
                pw.Text(c, style: const pw.TextStyle(fontSize: 9)))
            .toList())
        .toList();

    return pw.TableHelper.fromTextArray(
      headers: headerWidgets,
      data: dataRows,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      rowDecoration: const pw.BoxDecoration(),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
        bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      ),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
      },
      cellPadding:
          const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    );
  }
}
