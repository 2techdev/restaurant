// Template-level tests — render templates directly (without a service)
// and assert on the decoded ASCII substring.

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_printers/gastrocore_printers.dart';

String _ascii(List<int> bytes) {
  return bytes
      .where((b) => (b >= 0x20 && b < 0x7f) || b == 0x0a)
      .map((b) => String.fromCharCode(b))
      .join();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CapabilityProfile profile;
  setUpAll(() async {
    profile = await CapabilityProfile.load();
  });

  final cfgReceipt = PrinterConfig(
    id: 'r',
    storeId: 's',
    target: PrinterTarget.receipt,
    name: 'Fiş',
    ip: '10.0.0.1',
  );
  final cfgKitchen = PrinterConfig(
    id: 'k',
    storeId: 's',
    target: PrinterTarget.kitchen,
    name: 'Küche',
    ip: '10.0.0.2',
  );

  group('ReceiptTemplate', () {
    test('emits zero-bytes for empty items still closes with cut', () {
      final data = ReceiptData(
        storeName: 'A',
        storeAddress: 'X',
        storePhone: '',
        ticketNumber: 'R-1',
        issuedAt: DateTime(2026, 1, 1),
        items: const [],
        subtotalCents: 0,
        grandTotalCents: 0,
      );
      final bytes = ReceiptTemplate(cfgReceipt, profile).build(data);
      expect(bytes, isNotEmpty);
    });

    test('renders dine-in 8.1% MWST line', () {
      final data = ReceiptData(
        storeName: 'Zum Frohsinn',
        storeAddress: 'Zurich',
        storePhone: '+41',
        ticketNumber: 'R-1',
        tableLabel: 'Tisch 1',
        issuedAt: DateTime(2026, 1, 1),
        items: const [
          ReceiptLineItem(
            name: 'Rösti',
            quantity: 1,
            unitPriceCents: 2200,
            lineTotalCents: 2200,
          ),
        ],
        subtotalCents: 2200,
        grandTotalCents: 2200,
        taxLines: const [
          ReceiptTaxLine(
            label: 'MWST 8.1%',
            ratePercent: 8.1,
            netCents: 2035,
            taxCents: 165,
            grossCents: 2200,
          ),
        ],
      );
      final text = _ascii(ReceiptTemplate(cfgReceipt, profile).build(data));
      expect(text, contains('MWST 8.1'));
      expect(text, contains('TOTAL CHF'));
      expect(text, contains('22.00'));
    });

    test('renders takeaway 2.6% MWST line', () {
      final data = ReceiptData(
        storeName: 'S',
        storeAddress: '',
        storePhone: '',
        ticketNumber: 'R-1',
        issuedAt: DateTime(2026, 1, 1),
        items: const [
          ReceiptLineItem(
            name: 'X',
            quantity: 1,
            unitPriceCents: 1000,
            lineTotalCents: 1000,
          ),
        ],
        subtotalCents: 1000,
        grandTotalCents: 1000,
        taxLines: const [
          ReceiptTaxLine(
            label: 'MWST 2.6%',
            ratePercent: 2.6,
            netCents: 974,
            taxCents: 26,
            grossCents: 1000,
          ),
        ],
      );
      final text = _ascii(ReceiptTemplate(cfgReceipt, profile).build(data));
      expect(text, contains('MWST 2.6'));
    });

    test('QR payload triggers qrcode command (non-empty additional bytes)', () {
      final base = ReceiptData(
        storeName: 'S',
        storeAddress: '',
        storePhone: '',
        ticketNumber: 'R-1',
        issuedAt: DateTime(2026, 1, 1),
        items: const [
          ReceiptLineItem(
              name: 'X',
              quantity: 1,
              unitPriceCents: 100,
              lineTotalCents: 100),
        ],
        subtotalCents: 100,
        grandTotalCents: 100,
      );
      final withQr = ReceiptData(
        storeName: base.storeName,
        storeAddress: base.storeAddress,
        storePhone: base.storePhone,
        ticketNumber: base.ticketNumber,
        issuedAt: base.issuedAt,
        items: base.items,
        subtotalCents: base.subtotalCents,
        grandTotalCents: base.grandTotalCents,
        qrPayload: 'https://gastrocore.ch/i/R-1',
      );
      final a = ReceiptTemplate(cfgReceipt, profile).build(base).length;
      final b = ReceiptTemplate(cfgReceipt, profile).build(withQr).length;
      expect(b, greaterThan(a));
    });
  });

  group('KitchenTicketTemplate', () {
    test('renders gang labels in uppercase', () {
      final data = KitchenTicketData(
        ticketNumber: 'R-2',
        tableLabel: 'Tisch 3',
        guestCount: 2,
        firedAt: DateTime(2026, 1, 1),
        gangs: const [
          KitchenTicketGang(
            courseNumber: 1,
            label: 'Vorspeise',
            items: [KitchenTicketItem(name: 'Suppe', quantity: 2)],
          ),
        ],
      );
      final text = _ascii(KitchenTicketTemplate(cfgKitchen, profile).build(data));
      expect(text, contains('VORSPEISE'));
      expect(text, contains('Tisch 3'));
    });

    test('allergens appear with ALLERGEN label', () {
      final data = KitchenTicketData(
        ticketNumber: 'R-3',
        firedAt: DateTime(2026, 1, 1),
        gangs: const [
          KitchenTicketGang(
            courseNumber: 1,
            label: 'Main',
            items: [
              KitchenTicketItem(
                name: 'Nuts dish',
                quantity: 1,
                allergens: ['nuts', 'dairy'],
              ),
            ],
          ),
        ],
      );
      final text = _ascii(KitchenTicketTemplate(cfgKitchen, profile).build(data));
      expect(text, contains('ALLERGEN'));
      expect(text, contains('nuts'));
      expect(text, contains('dairy'));
    });

    test('re-fire ticket renders NEUAUSDRUCK banner', () {
      final data = KitchenTicketData(
        ticketNumber: 'R-4',
        firedAt: DateTime(2026, 1, 1),
        isFireDelta: false,
        gangs: const [
          KitchenTicketGang(
            courseNumber: 1,
            label: 'M',
            items: [KitchenTicketItem(name: 'X', quantity: 1)],
          ),
        ],
      );
      final text = _ascii(KitchenTicketTemplate(cfgKitchen, profile).build(data));
      expect(text, contains('NEUAUSDRUCK'));
    });
  });
}
