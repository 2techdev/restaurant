/// Excel report generator for the Analytics screen.
///
/// Uses the `excel` package to build a multi-sheet workbook and saves it to
/// the app's temporary directory, returning the file path for display.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'package:gastrocore_pos/features/dashboard/domain/entities/analytics_report.dart';

final _chf = NumberFormat('#,##0.00', 'de_CH');
final _dateFmt = DateFormat('dd.MM.yyyy');

String _fChf(int cents) => _chf.format(cents / 100);

class ExcelExporter {
  ExcelExporter._();

  /// Build the workbook and save to temp directory.
  /// Returns the full file path.
  static Future<String> exportReport(AnalyticsReport report) async {
    final bytes = _build(report);
    final dir = await getTemporaryDirectory();
    final dateStr = _dateFmt
        .format(report.dateRange.start)
        .replaceAll('.', '-');
    final path = '${dir.path}/GastroCore_Report_$dateStr.xlsx';
    final file = File(path);
    await file.writeAsBytes(bytes);
    return path;
  }

  // ---------------------------------------------------------------------------
  // Build workbook
  // ---------------------------------------------------------------------------

  static Uint8List _build(AnalyticsReport report) {
    final excel = Excel.createExcel();

    // Remove default 'Sheet1' after we add our sheets.
    _buildSummarySheet(excel, report);
    _buildTrendSheet(excel, report);
    _buildProductsSheet(excel, report);
    _buildPaymentsSheet(excel, report);
    _buildMwstSheet(excel, report);
    _buildStaffSheet(excel, report);
    _buildHourlySheet(excel, report);

    // Remove auto-created Sheet1 if it exists and is empty.
    if (excel.sheets.containsKey('Sheet1') &&
        (excel.sheets['Sheet1']?.maxRows ?? 0) == 0) {
      excel.delete('Sheet1');
    }

    final encoded = excel.encode();
    return Uint8List.fromList(encoded!);
  }

  // ---------------------------------------------------------------------------
  // Sheets
  // ---------------------------------------------------------------------------

  static void _buildSummarySheet(Excel excel, AnalyticsReport r) {
    final sheet = excel['Özet'];
    _title(sheet, 'GastroCore – Analytics Raporu');
    _blank(sheet);
    _row(sheet, ['Dönem', r.dateRange.label]);
    _row(sheet, [
      'Tarih Aralığı',
      '${_dateFmt.format(r.dateRange.start)} – '
          '${_dateFmt.format(r.dateRange.end.subtract(const Duration(days: 1)))}'
    ]);
    _blank(sheet);
    _header(sheet, ['KPI', 'Değer']);
    _row(sheet, ['Toplam Ciro (CHF)', _fChf(r.totalRevenueCents)]);
    _row(sheet, ['Tamamlanan Sipariş', r.completedOrderCount]);
    _row(sheet, ['İptal Edilen', r.cancelledOrderCount]);
    _row(sheet, ['Void', r.voidedOrderCount]);
    _row(sheet, ['Ort. Sipariş (CHF)', _fChf(r.avgOrderCents)]);
    _row(sheet, [
      'İptal Oranı (%)',
      (r.cancellationRate * 100).toStringAsFixed(1)
    ]);
    _row(sheet, [
      'Masa Doluluk (%)',
      (r.tableOccupancyRate * 100).toStringAsFixed(1)
    ]);
  }

  static void _buildTrendSheet(Excel excel, AnalyticsReport r) {
    final sheet = excel['Günlük Trend'];
    _header(sheet, ['Tarih', 'Ciro (CHF)', 'Sipariş Sayısı']);
    for (final p in r.dailyTrend) {
      _row(sheet, [
        _dateFmt.format(p.date),
        _fChf(p.revenueCents),
        p.orderCount,
      ]);
    }
  }

  static void _buildProductsSheet(Excel excel, AnalyticsReport r) {
    final sheet = excel['Top Ürünler'];
    _header(sheet, ['Sıra', 'Ürün Adı', 'Miktar', 'Ciro (CHF)']);
    for (var i = 0; i < r.topProducts.length; i++) {
      final p = r.topProducts[i];
      _row(sheet, [
        i + 1,
        p.productName,
        p.quantity,
        _fChf(p.revenueCents),
      ]);
    }
  }

  static void _buildPaymentsSheet(Excel excel, AnalyticsReport r) {
    final sheet = excel['Ödeme Yöntemleri'];
    const labels = {
      'cash': 'Nakit',
      'credit_card': 'Kredi Kartı',
      'debit_card': 'Banka Kartı',
      'twint': 'TWINT',
    };
    _header(sheet, ['Yöntem', 'İşlem Sayısı', 'Toplam (CHF)']);
    for (final p in r.paymentBreakdown) {
      _row(sheet, [
        labels[p.method] ?? p.method,
        p.count,
        _fChf(p.amountCents),
      ]);
    }
  }

  static void _buildMwstSheet(Excel excel, AnalyticsReport r) {
    final sheet = excel['MWST Raporu'];
    _header(sheet, [
      'Kategori',
      'Brüt (CHF)',
      'MWST (CHF)',
      'Net (CHF)',
      'Oran (%)',
    ]);
    for (final m in r.mwstReport) {
      _row(sheet, [
        m.label,
        _fChf(m.grossRevenueCents),
        _fChf(m.taxCents),
        _fChf(m.netRevenueCents),
        m.effectiveRatePct.toStringAsFixed(2),
      ]);
    }
  }

  static void _buildStaffSheet(Excel excel, AnalyticsReport r) {
    final sheet = excel['Personel'];
    _header(sheet, [
      'Personel',
      'Sipariş Sayısı',
      'Toplam Ciro (CHF)',
      'Ort. Sipariş (CHF)',
      'Ort. Süre (dk)',
    ]);
    for (final s in r.staffPerformance) {
      _row(sheet, [
        s.waiterName,
        s.orderCount,
        _fChf(s.revenueCents),
        _fChf(s.avgOrderCents),
        s.avgDurationMinutes,
      ]);
    }
  }

  static void _buildHourlySheet(Excel excel, AnalyticsReport r) {
    final sheet = excel['Saatlik Yoğunluk'];
    _header(sheet, ['Saat', 'Ciro (CHF)', 'Sipariş Sayısı']);
    for (final h in r.hourlySales) {
      _row(sheet, [
        '${h.hour.toString().padLeft(2, '0')}:00',
        _fChf(h.amountCents),
        h.orderCount,
      ]);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static void _title(Sheet sheet, String text) {
    sheet.appendRow([TextCellValue(text)]);
  }

  static void _blank(Sheet sheet) {
    sheet.appendRow([TextCellValue('')]);
  }

  static void _header(Sheet sheet, List<String> cols) {
    sheet.appendRow(cols.map((c) => TextCellValue(c)).toList());
  }

  static void _row(Sheet sheet, List<dynamic> values) {
    sheet.appendRow(values.map((v) {
      if (v is int) return IntCellValue(v);
      if (v is double) return DoubleCellValue(v);
      return TextCellValue(v.toString());
    }).toList());
  }
}
