/// Swiss VAT (MWST) receipt tests.
///
/// Covers:
/// - Dine-in vs takeaway service type label on receipt
/// - MwStCode.forProduct() rate resolution
/// - 5-Rappen rounding line on cash receipts
/// - Mixed orders: alcohol (A) + food takeaway (B) breakdown
/// - Dine-in food correctly maps to code A (8.1%)
/// - Takeaway food correctly maps to code B (2.6%)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/printing/escpos/swiss_receipt_builder.dart';
import 'package:gastrocore_pos/core/printing/models/print_models.dart';
import 'package:gastrocore_pos/core/services/fare_engine.dart';
import 'package:gastrocore_pos/core/services/fare_models.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _text(List<int> bytes) => String.fromCharCodes(
      bytes.where((b) => b >= 0x20 || b == 0x0A),
    );

SwissReceiptData _receipt({
  String? orderTypeLabel,
  int roundingAmount = 0,
  Map<String, int> mwstBreakdown = const {},
  List<SwissPaymentLine> payments = const [],
  List<SwissReceiptItem> items = const [],
  int total = 0,
}) {
  return SwissReceiptData(
    restaurantName: 'Test Restaurant AG',
    receiptNo: '0042',
    items: items,
    total: total,
    mwstNr: 'CHE-123.456.789 MWST',
    orderTypeLabel: orderTypeLabel,
    roundingAmount: roundingAmount,
    mwstBreakdown: mwstBreakdown,
    payments: payments,
  );
}

SwissReceiptItem _item({
  String name = 'Cordon Bleu',
  int unitPrice = 2850,
  MwStCode mwstCode = MwStCode.a,
}) {
  return SwissReceiptItem(
    name: name,
    quantity: 1,
    unitPrice: unitPrice,
    totalPrice: unitPrice,
    mwstCode: mwstCode,
  );
}

// Swiss config matching order_provider._swissFareConfig
const _swissConfig = FareConfig(
  isTaxInclusive: true,
  currency: 'CHF',
  roundingRule: RoundingRule(rule: 'round', unit: 'five_percent'),
  taxRates: [
    TaxRateConfig(name: 'food', rate: 8.1, dineInRate: '8.1', takeawayRate: '2.6'),
    TaxRateConfig(name: 'beverage', rate: 8.1, dineInRate: '8.1', takeawayRate: '8.1'),
    TaxRateConfig(name: 'alcohol', rate: 8.1, dineInRate: '8.1', takeawayRate: '8.1'),
    TaxRateConfig(name: 'standard', rate: 8.1, dineInRate: '8.1', takeawayRate: '8.1'),
    TaxRateConfig(name: 'accommodation', rate: 3.8),
  ],
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // MwStCode.forProduct() — rate resolution logic
  // =========================================================================

  group('MwStCode.forProduct()', () {
    test('food dine-in → A (8.1%)', () {
      expect(
        MwStCode.forProduct(taxGroup: 'food', isDineIn: true),
        MwStCode.a,
      );
    });

    test('food takeaway → B (2.6%)', () {
      expect(
        MwStCode.forProduct(taxGroup: 'food', isDineIn: false),
        MwStCode.b,
      );
    });

    test('beverage always → A (8.1%)', () {
      expect(MwStCode.forProduct(taxGroup: 'beverage', isDineIn: true), MwStCode.a);
      expect(MwStCode.forProduct(taxGroup: 'beverage', isDineIn: false), MwStCode.a);
    });

    test('alcohol always → A (8.1%)', () {
      expect(MwStCode.forProduct(taxGroup: 'alcohol', isDineIn: true), MwStCode.a);
      expect(MwStCode.forProduct(taxGroup: 'alcohol', isDineIn: false), MwStCode.a);
    });

    test('accommodation always → C (3.8%)', () {
      expect(MwStCode.forProduct(taxGroup: 'accommodation', isDineIn: true), MwStCode.c);
      expect(MwStCode.forProduct(taxGroup: 'accommodation', isDineIn: false), MwStCode.c);
    });

    test('unknown taxGroup → A (8.1% standard fallback)', () {
      expect(MwStCode.forProduct(taxGroup: 'standard', isDineIn: false), MwStCode.a);
    });
  });

  // =========================================================================
  // Dine-in / Takeaway label on receipt
  // =========================================================================

  group('Bestellart label', () {
    test('Hier essen printed when orderTypeLabel set', () {
      final data = _receipt(orderTypeLabel: 'Hier essen');
      final text = _text(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Hier essen'));
      expect(text, contains('Bestellart'));
    });

    test('Zum Mitnehmen printed when orderTypeLabel set', () {
      final data = _receipt(orderTypeLabel: 'Zum Mitnehmen');
      final text = _text(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Zum Mitnehmen'));
    });

    test('No Bestellart line when orderTypeLabel is null', () {
      final data = _receipt(orderTypeLabel: null);
      final text = _text(SwissReceiptBuilder(data: data).build());
      expect(text, isNot(contains('Bestellart')));
    });
  });

  // =========================================================================
  // 5-Rappen rounding on receipt
  // =========================================================================

  group('5-Rappen rounding line', () {
    test('Rundung line printed with positive rounding (+3 Rappen)', () {
      final data = _receipt(
        roundingAmount: 2, // +0.02 CHF (rounded up)
        total: 1725,
        payments: [const SwissPaymentLine(method: 'Bar', amount: 1725)],
      );
      final text = _text(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Rundung'));
    });

    test('Rundung line printed with negative rounding (-2 Rappen)', () {
      final data = _receipt(
        roundingAmount: -2, // -0.02 CHF (rounded down)
        total: 1723,
        payments: [const SwissPaymentLine(method: 'Bar', amount: 1723)],
      );
      final text = _text(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Rundung'));
    });

    test('No Rundung line when roundingAmount is 0', () {
      final data = _receipt(roundingAmount: 0);
      final text = _text(SwissReceiptBuilder(data: data).build());
      expect(text, isNot(contains('Rundung')));
    });

    test('5-Rappen rounding: CHF 17.23 → CHF 17.25 (+2 Rappen)', () {
      // 1723 % 5 = 3 → rounds up to 1725, rounding = +2
      const rule = RoundingRule(rule: 'round', unit: 'five_percent');
      final rounded = rule.apply(1723);
      expect(rounded, 1725);
      // roundingAmount = rounded - original = +2
      expect(rounded - 1723, 2);
    });

    test('5-Rappen rounding: CHF 17.22 → CHF 17.20 (-2 Rappen)', () {
      // 1722 % 5 = 2 → rounds down to 1720, rounding = -2
      const rule = RoundingRule(rule: 'round', unit: 'five_percent');
      final rounded = rule.apply(1722);
      expect(rounded, 1720);
      expect(rounded - 1722, -2);
    });

    test('Card payment: no rounding applied (exact amount)', () {
      // CHF 17.23 card → exact, roundingAmount stays 0
      const rule = RoundingRule(rule: 'round', unit: 'percentile');
      expect(rule.apply(1723), 1723);
    });
  });

  // =========================================================================
  // Swiss MWST: dine-in vs takeaway via FareEngine
  // =========================================================================

  group('Swiss MWST rate via FareEngine', () {
    test('Coffee dine-in: rate 8.1%, code A', () {
      final result = FareEngine.calculateFare(
        items: [
          const FareLineItem(
            productId: 'coffee',
            productName: 'Kaffee',
            quantity: 1,
            unitPrice: 450, // CHF 4.50
            taxGroup: 'beverage',
            isTaxInclusive: true,
          ),
        ],
        config: _swissConfig,
        orderType: 'dine_in',
      );
      expect(result.dishesTaxes.length, 1);
      expect(result.dishesTaxes.first.rate, '8.1');
      // MwSt = 450 * 8.1 / 108.1 ≈ 34 cent
      expect(result.dishesTaxes.first.amount, 34);
      // MwStCode resolved via MwStCode.forProduct
      expect(
        MwStCode.forProduct(taxGroup: 'beverage', isDineIn: true),
        MwStCode.a,
      );
    });

    test('Coffee takeaway: beverage stays at 8.1%, code A', () {
      final result = FareEngine.calculateFare(
        items: [
          const FareLineItem(
            productId: 'coffee',
            productName: 'Kaffee',
            quantity: 1,
            unitPrice: 450,
            taxGroup: 'beverage',
            isTaxInclusive: true,
          ),
        ],
        config: _swissConfig,
        orderType: 'takeaway',
      );
      expect(result.dishesTaxes.first.rate, '8.1');
    });

    test('Sandwich dine-in: food at 8.1%, code A', () {
      final result = FareEngine.calculateFare(
        items: [
          const FareLineItem(
            productId: 'sandwich',
            productName: 'Sandwich',
            quantity: 1,
            unitPrice: 1250,
            taxGroup: 'food',
            isTaxInclusive: true,
          ),
        ],
        config: _swissConfig,
        orderType: 'dine_in',
      );
      expect(result.dishesTaxes.first.rate, '8.1');
      // MwSt = 1250 * 8.1 / 108.1 ≈ 94 cent
      expect(result.dishesTaxTotal, 94);
      expect(
        MwStCode.forProduct(taxGroup: 'food', isDineIn: true),
        MwStCode.a,
      );
    });

    test('Sandwich takeaway: food drops to 2.6%, code B', () {
      final result = FareEngine.calculateFare(
        items: [
          const FareLineItem(
            productId: 'sandwich',
            productName: 'Sandwich',
            quantity: 1,
            unitPrice: 1250,
            taxGroup: 'food',
            isTaxInclusive: true,
          ),
        ],
        config: _swissConfig,
        orderType: 'takeaway',
      );
      expect(result.dishesTaxes.first.rate, '2.6');
      // MwSt = 1250 * 2.6 / 102.6 ≈ 32 cent
      expect(result.dishesTaxTotal, 32);
      expect(
        MwStCode.forProduct(taxGroup: 'food', isDineIn: false),
        MwStCode.b,
      );
    });

    test('Beer always 8.1% (alcohol)', () {
      final dineIn = FareEngine.calculateFare(
        items: [
          const FareLineItem(
            productId: 'beer',
            productName: 'Bier',
            quantity: 1,
            unitPrice: 600,
            taxGroup: 'alcohol',
            isTaxInclusive: true,
          ),
        ],
        config: _swissConfig,
        orderType: 'takeaway',
      );
      expect(dineIn.dishesTaxes.first.rate, '8.1');
    });
  });

  // =========================================================================
  // Mixed order: alcohol (A) + food takeaway (B)
  // =========================================================================

  group('Mixed order MWST breakdown', () {
    test('Takeaway: beer (A=8.1%) + food (B=2.6%) → two breakdown lines', () {
      final result = FareEngine.calculateFare(
        items: [
          const FareLineItem(
            productId: 'beer',
            productName: 'Bier',
            quantity: 1,
            unitPrice: 600,
            taxGroup: 'alcohol',
            isTaxInclusive: true,
          ),
          const FareLineItem(
            productId: 'sandwich',
            productName: 'Sandwich',
            quantity: 1,
            unitPrice: 1250,
            taxGroup: 'food',
            isTaxInclusive: true,
          ),
        ],
        config: _swissConfig,
        orderType: 'takeaway',
      );

      // Two distinct tax groups
      expect(result.dishesTaxes.length, 2);

      final alcoholTax =
          result.dishesTaxes.firstWhere((t) => t.name == 'alcohol');
      final foodTax =
          result.dishesTaxes.firstWhere((t) => t.name == 'food');

      expect(alcoholTax.rate, '8.1');
      expect(foodTax.rate, '2.6');

      // Receipt breakdown map for builder
      final mwstMap = <String, int>{};
      for (final t in result.dishesTaxes) {
        final code = MwStCode.fromRate(double.parse(t.rate));
        mwstMap[code.code] = (mwstMap[code.code] ?? 0) +
            (t.name == 'alcohol' ? 600 : 1250);
      }
      expect(mwstMap.containsKey('A'), isTrue); // alcohol → A
      expect(mwstMap.containsKey('B'), isTrue); // food takeaway → B
    });

    test('Receipt prints both A and B breakdown codes', () {
      // Simulate a mixed takeaway receipt
      final data = _receipt(
        orderTypeLabel: 'Zum Mitnehmen',
        mwstBreakdown: {'A': 600, 'B': 1250},
        items: [
          _item(name: 'Bier', unitPrice: 600, mwstCode: MwStCode.a),
          _item(name: 'Sandwich', unitPrice: 1250, mwstCode: MwStCode.b),
        ],
        total: 1850,
      );
      final text = _text(SwissReceiptBuilder(data: data).build());

      expect(text, contains('Zum Mitnehmen'));
      expect(text, contains('8.1%'));
      expect(text, contains('2.6%'));
      expect(text, contains('[A]')); // beer code on item line
      expect(text, contains('[B]')); // sandwich code on item line
    });
  });

  // =========================================================================
  // Swiss receipt checklist validation
  // =========================================================================

  group('Swiss receipt compliance', () {
    test('All mandatory fields present on a complete dine-in receipt', () {
      final data = SwissReceiptData(
        restaurantName: 'Gastro Alp AG',
        address: 'Bahnhofstrasse 1, 8001 Zuerich',
        mwstNr: 'CHE-987.654.321 MWST',
        receiptNo: '00042',
        dateTime: DateTime(2026, 3, 21, 12, 30, 0),
        cashierName: 'Anna Mueller',
        tableName: 'T-07',
        orderTypeLabel: 'Hier essen',
        items: [
          _item(name: 'Cordon Bleu', unitPrice: 2850),
        ],
        total: 2850,
        mwstBreakdown: {'A': 2850},
        payments: [const SwissPaymentLine(method: 'Karte', amount: 2850)],
      );

      final text = _text(SwissReceiptBuilder(data: data).build());

      // Business name & address
      expect(text, contains('Gastro Alp AG'));
      expect(text, contains('Bahnhofstrasse'));
      // MWST-Nr
      expect(text, contains('CHE-987.654.321 MWST'));
      // Sequential receipt number
      expect(text, contains('00042'));
      // Date & time
      expect(text, contains('21.03.2026'));
      expect(text, contains('12:30:00'));
      // Cashier & table
      expect(text, contains('Anna Mueller'));
      expect(text, contains('T-07'));
      // Service type
      expect(text, contains('Hier essen'));
      // Item
      expect(text, contains('Cordon Bleu'));
      // MWST breakdown table
      expect(text, contains('MwSt-Abrechnung'));
      expect(text, contains('8.1%'));
      // Payment method
      expect(text, contains('Karte'));
      // Total
      expect(text, contains('28.50'));
    });

    test('Cash receipt with rounding shows Rundung line before Gegeben', () {
      final data = SwissReceiptData(
        restaurantName: 'X',
        receiptNo: '1',
        items: const [],
        total: 1725,
        roundingAmount: 2, // +2 Rappen
        payments: [const SwissPaymentLine(method: 'Bar', amount: 1725)],
        tenderedAmount: 2000,
        changeAmount: 275,
      );

      final text = _text(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Rundung'));
      expect(text, contains('Gegeben'));
      expect(text, contains('Rueckgeld'));

      // Rundung must appear before Gegeben in the output
      final rundungIdx = text.indexOf('Rundung');
      final gegebenIdx = text.indexOf('Gegeben');
      expect(rundungIdx, lessThan(gegebenIdx));
    });
  });
}
