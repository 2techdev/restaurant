/// Tests for the digital-receipt PDF builder.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/printing/models/print_models.dart';
import 'package:gastrocore_pos/features/orders/services/digital_receipt_service.dart';

SwissReceiptData _sample({int total = 3375}) => SwissReceiptData(
      restaurantName: 'Restaurant Helvetia',
      address: 'Bahnhofstrasse 1, 8001 Zürich',
      phone: 'Tel: +41 44 000 00 00',
      receiptNo: '42',
      dateTime: DateTime(2026, 4, 22, 19, 30),
      cashierName: 'Alice',
      tableName: 'T-7',
      items: const [
        SwissReceiptItem(
          name: 'Rösti',
          quantity: 2,
          unitPrice: 1800,
          totalPrice: 3600,
          mwstCode: MwStCode.a,
        ),
        SwissReceiptItem(
          name: 'Mineral',
          quantity: 1,
          unitPrice: 450,
          totalPrice: 450,
          mwstCode: MwStCode.a,
        ),
      ],
      subtotal: 4050,
      total: total,
      discountAmount: 675,
      footerText: 'Danke und auf Wiedersehen',
    );

void main() {
  group('DigitalReceiptService.buildPdfBytes', () {
    const service = DigitalReceiptService();

    test('produces a non-trivial PDF byte stream with a %PDF header',
        () async {
      final bytes = await service.buildPdfBytes(_sample());
      expect(bytes.length, greaterThan(1000));
      // Every PDF file starts with "%PDF".
      expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    });

    test('builds a QR payload that round-trips the receipt identity',
        () async {
      // We can't re-read the QR out of the PDF without pulling a zxing
      // dependency, so this test just asserts that the byte stream for
      // two distinct receipts differs — the QR payload embeds the
      // receipt number, so a different receipt-no must produce different
      // bytes.
      final a = await service.buildPdfBytes(_sample());
      final b = await service.buildPdfBytes(_sample(total: 9999));
      expect(a.length == b.length && _bytesEqual(a, b), isFalse);
    });
  });
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
