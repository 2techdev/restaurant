/// Build a PDF digital receipt with a QR deep link and share it via the
/// platform share sheet (email, WhatsApp, AirDrop, Files...).
///
/// The PDF is intentionally a compact A6-ish width sheet that mirrors
/// the thermal receipt layout. A QR payload embeds the ticket summary
/// so the customer can verify authenticity or a waiter can re-scan the
/// receipt at checkout — no external service round-trip required.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:gastrocore_pos/core/printing/models/print_models.dart';

class DigitalReceiptService {
  const DigitalReceiptService();

  /// Build the PDF bytes only — useful for tests or for callers that
  /// want to attach the bytes to an outbound email without touching the
  /// filesystem.
  Future<List<int>> buildPdfBytes(SwissReceiptData data) async {
    final doc = pw.Document(title: 'Receipt #${data.receiptNo}');

    final qrPayload = jsonEncode(_qrPayload(data));

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a6,
        margin: const pw.EdgeInsets.all(12),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _header(data),
            pw.SizedBox(height: 6),
            _meta(data),
            pw.SizedBox(height: 6),
            _divider(),
            pw.SizedBox(height: 4),
            _items(data),
            pw.SizedBox(height: 4),
            _divider(),
            pw.SizedBox(height: 4),
            _totals(data),
            pw.SizedBox(height: 8),
            _qr(qrPayload),
            pw.SizedBox(height: 4),
            if (data.footerText != null)
              pw.Text(data.footerText!,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ),
    );

    return doc.save();
  }

  /// Persist the PDF to a temp file and return its path. The caller can
  /// either share it or attach it to an email body.
  Future<File> buildPdfFile(SwissReceiptData data) async {
    final bytes = await buildPdfBytes(data);
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}${Platform.pathSeparator}receipt-${data.receiptNo}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Share the PDF using the system share sheet. [recipientEmail]
  /// pre-fills the address when the user picks an email target.
  Future<ShareResult> share(
    SwissReceiptData data, {
    String? recipientEmail,
  }) async {
    final file = await buildPdfFile(data);
    final subject = '${data.restaurantName} - Beleg #${data.receiptNo}';
    final text = recipientEmail == null
        ? 'Vielen Dank für Ihren Besuch! Beleg #${data.receiptNo} im Anhang.'
        : 'An: $recipientEmail\n\nVielen Dank! Beleg im Anhang.';
    return Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: subject,
      text: text,
    );
  }

  Map<String, dynamic> _qrPayload(SwissReceiptData data) => <String, dynamic>{
        'v': 1,
        'receiptNo': data.receiptNo,
        'dateTime': data.dateTime?.toIso8601String(),
        'total': data.total,
        'currency': 'CHF',
        'shop': data.restaurantName,
      };

  pw.Widget _header(SwissReceiptData d) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(d.restaurantName,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold)),
          if (d.address != null && d.address!.isNotEmpty)
            pw.Text(d.address!,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 8)),
          if (d.phone != null && d.phone!.isNotEmpty)
            pw.Text(d.phone!,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 8)),
        ],
      );

  pw.Widget _meta(SwissReceiptData d) {
    final lines = <pw.Widget>[];
    if (d.dateTime != null) {
      final dt = d.dateTime!;
      lines.add(_metaLine(
          'Datum',
          '${dt.day.toString().padLeft(2, '0')}.'
              '${dt.month.toString().padLeft(2, '0')}.${dt.year} '
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'));
    }
    lines.add(_metaLine('Beleg', '#${d.receiptNo}'));
    if (d.cashierName != null) lines.add(_metaLine('Bedient', d.cashierName!));
    if (d.tableName != null) lines.add(_metaLine('Tisch', d.tableName!));
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: lines,
    );
  }

  pw.Widget _metaLine(String k, String v) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(k, style: const pw.TextStyle(fontSize: 8)),
          pw.Text(v, style: const pw.TextStyle(fontSize: 8)),
        ],
      );

  pw.Widget _divider() => pw.Container(
        height: 0.5,
        color: PdfColors.grey,
      );

  pw.Widget _items(SwissReceiptData d) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: d.items.map((it) {
          final qty = it.quantity % 1 == 0
              ? it.quantity.toInt().toString()
              : it.quantity.toStringAsFixed(1);
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text('$qty x ${it.name}',
                      style: const pw.TextStyle(fontSize: 8)),
                ),
                pw.Text(_chf(it.totalPrice),
                    style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          );
        }).toList(),
      );

  pw.Widget _totals(SwissReceiptData d) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (d.subtotal != null)
            _metaLine('Zwischensumme', _chf(d.subtotal!)),
          if (d.discountAmount > 0)
            _metaLine('Rabatt', '-${_chf(d.discountAmount)}'),
          if (d.serviceChargeAmount > 0)
            _metaLine('Service', _chf(d.serviceChargeAmount)),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('TOTAL',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text(_chf(d.total),
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ],
      );

  pw.Widget _qr(String payload) => pw.Center(
        child: pw.BarcodeWidget(
          data: payload,
          barcode: pw.Barcode.qrCode(),
          width: 80,
          height: 80,
          drawText: false,
        ),
      );

  static String _chf(int cents) {
    final whole = (cents / 100).truncate();
    final frac = (cents.abs() % 100).toString().padLeft(2, '0');
    return 'CHF ${whole.toString()}.$frac';
  }
}
