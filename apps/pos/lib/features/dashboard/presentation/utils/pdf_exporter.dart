/// PDF report generator for the Analytics screen.
///
/// Uses the `pdf` package (pw widgets) to build a multi-section report and
/// the `printing` package to share / print it via the native OS dialog.
library;

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:gastrocore_pos/features/dashboard/domain/entities/analytics_report.dart';

final _chf = NumberFormat.currency(locale: 'de_CH', symbol: 'CHF ', decimalDigits: 2);
final _dateFmt = DateFormat('dd.MM.yyyy');
final _pct = NumberFormat('0.0%');

String _fChf(int cents) => _chf.format(cents / 100);

class PdfExporter {
  PdfExporter._();

  /// Generate a PDF report and open the native share/print dialog.
  static Future<void> shareReport(AnalyticsReport report) async {
    final bytes = await _build(report);
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'GastroCore_Report_${_dateFmt.format(report.dateRange.start)}.pdf',
    );
  }

  // ---------------------------------------------------------------------------
  // Document builder
  // ---------------------------------------------------------------------------

  static Future<Uint8List> _build(AnalyticsReport report) async {
    final pdf = pw.Document(
      title: 'GastroCore Analytics Report',
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
          _header(report),
          pw.SizedBox(height: 16),
          _kpiRow(report),
          pw.SizedBox(height: 20),
          _section('Günlük Trend'),
          _trendTable(report),
          pw.SizedBox(height: 16),
          _section('En Çok Satan Ürünler (Top 10)'),
          _productsTable(report),
          pw.SizedBox(height: 16),
          _section('Ödeme Yöntemi Dağılımı'),
          _paymentsTable(report),
          pw.SizedBox(height: 16),
          _section('MWST Raporu'),
          _mwstTable(report),
          pw.SizedBox(height: 16),
          _section('Personel Performansı'),
          _staffTable(report),
        ],
      ),
    );

    return pdf.save();
  }

  // ---------------------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------------------

  static pw.Widget _header(AnalyticsReport r) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'GastroCore – Analytics Raporu',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${r.dateRange.label}: ${_dateFmt.format(r.dateRange.start)} – '
            '${_dateFmt.format(r.dateRange.end.subtract(const Duration(days: 1)))}',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
          ),
          pw.Divider(),
        ],
      );

  static pw.Widget _kpiRow(AnalyticsReport r) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _kpiBox('Toplam Ciro', _fChf(r.totalRevenueCents)),
          _kpiBox('Sipariş', r.completedOrderCount.toString()),
          _kpiBox('Ort. Sipariş', _fChf(r.avgOrderCents)),
          _kpiBox('İptal Oranı', _pct.format(r.cancellationRate)),
          _kpiBox(
              'Masa Doluluk', _pct.format(r.tableOccupancyRate)),
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
                    fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  static pw.Widget _section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(
          title,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      );

  static pw.Widget _trendTable(AnalyticsReport r) {
    if (r.dailyTrend.isEmpty) return _empty();
    return _table(
      headers: ['Tarih', 'Ciro (CHF)', 'Sipariş'],
      rows: r.dailyTrend.map((p) => [
            _dateFmt.format(p.date),
            _fChf(p.revenueCents),
            p.orderCount.toString(),
          ]).toList(),
    );
  }

  static pw.Widget _productsTable(AnalyticsReport r) {
    if (r.topProducts.isEmpty) return _empty();
    return _table(
      headers: ['Ürün', 'Miktar', 'Ciro (CHF)'],
      rows: r.topProducts.map((p) => [
            p.productName,
            p.quantity.toStringAsFixed(p.quantity % 1 == 0 ? 0 : 2),
            _fChf(p.revenueCents),
          ]).toList(),
    );
  }

  static pw.Widget _paymentsTable(AnalyticsReport r) {
    if (r.paymentBreakdown.isEmpty) return _empty();
    final labels = {
      'cash': 'Nakit',
      'credit_card': 'Kredi Kartı',
      'debit_card': 'Banka Kartı',
      'twint': 'TWINT',
    };
    return _table(
      headers: ['Yöntem', 'İşlem Sayısı', 'Toplam (CHF)'],
      rows: r.paymentBreakdown.map((p) => [
            labels[p.method] ?? p.method,
            p.count.toString(),
            _fChf(p.amountCents),
          ]).toList(),
    );
  }

  static pw.Widget _mwstTable(AnalyticsReport r) {
    if (r.mwstReport.isEmpty) return _empty();
    return _table(
      headers: ['Kategori', 'Brüt (CHF)', 'MWST (CHF)', 'Net (CHF)', 'Oran %'],
      rows: r.mwstReport.map((m) => [
            m.label,
            _fChf(m.grossRevenueCents),
            _fChf(m.taxCents),
            _fChf(m.netRevenueCents),
            m.effectiveRatePct.toStringAsFixed(1),
          ]).toList(),
    );
  }

  static pw.Widget _staffTable(AnalyticsReport r) {
    if (r.staffPerformance.isEmpty) return _empty();
    return _table(
      headers: ['Personel', 'Sipariş', 'Ciro (CHF)', 'Ort. CHF', 'Ort. Süre'],
      rows: r.staffPerformance.map((s) => [
            s.waiterName,
            s.orderCount.toString(),
            _fChf(s.revenueCents),
            _fChf(s.avgOrderCents),
            '${s.avgDurationMinutes} dk',
          ]).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static pw.Widget _empty() => pw.Text(
        'Veri yok.',
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

    final dataRows = rows.map((row) {
      return row
          .map((cell) => pw.Text(cell,
              style: const pw.TextStyle(fontSize: 9)))
          .toList();
    }).toList();

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
