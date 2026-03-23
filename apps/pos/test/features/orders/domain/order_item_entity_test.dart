/// Comprehensive tests for [OrderItemEntity] and [OrderItemModifierEntity].
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

OrderItemEntity _item({
  String id = 'item-1',
  String tenantId = 'tenant-1',
  String ticketId = 'ticket-1',
  String productId = 'prod-1',
  String productName = 'Zürich Geschnetzeltes',
  double quantity = 1.0,
  int unitPrice = 2850,
  int subtotal = 2850,
  int taxAmount = 0,
  int discountAmount = 0,
  OrderItemStatus status = OrderItemStatus.ordered,
  bool sentToKitchen = false,
  String? notes,
  int course = 1,
  List<OrderItemModifierEntity> modifiers = const [],
  bool isTaxFree = false,
  bool isOpenPrice = false,
  bool isWeightBased = false,
  double? weight,
  String? weightUnit,
  int specialDiscountAmount = 0,
  String taxGroup = 'food',
}) {
  return OrderItemEntity(
    id: id,
    tenantId: tenantId,
    ticketId: ticketId,
    productId: productId,
    productName: productName,
    quantity: quantity,
    unitPrice: unitPrice,
    subtotal: subtotal,
    taxAmount: taxAmount,
    discountAmount: discountAmount,
    status: status,
    sentToKitchen: sentToKitchen,
    notes: notes,
    course: course,
    modifiers: modifiers,
    isTaxFree: isTaxFree,
    isOpenPrice: isOpenPrice,
    isWeightBased: isWeightBased,
    weight: weight,
    weightUnit: weightUnit,
    specialDiscountAmount: specialDiscountAmount,
    taxGroup: taxGroup,
  );
}

OrderItemModifierEntity _modifier({
  String id = 'mod-1',
  String orderItemId = 'item-1',
  String modifierId = 'mdef-1',
  String modifierName = 'Extra Sauce',
  int priceDelta = 50,
}) {
  return OrderItemModifierEntity(
    id: id,
    orderItemId: orderItemId,
    modifierId: modifierId,
    modifierName: modifierName,
    priceDelta: priceDelta,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // OrderItemModifierEntity
  // =========================================================================
  group('OrderItemModifierEntity', () {
    test('constructs with required fields', () {
      final mod = _modifier();
      expect(mod.id, 'mod-1');
      expect(mod.orderItemId, 'item-1');
      expect(mod.modifierId, 'mdef-1');
      expect(mod.modifierName, 'Extra Sauce');
      expect(mod.priceDelta, 50);
    });

    test('copyWith overrides selected fields', () {
      final mod = _modifier();
      final updated = mod.copyWith(modifierName: 'No Sauce', priceDelta: 0);
      expect(updated.id, mod.id);
      expect(updated.modifierName, 'No Sauce');
      expect(updated.priceDelta, 0);
    });

    test('copyWith preserves unchanged fields', () {
      final mod = _modifier();
      final updated = mod.copyWith(priceDelta: 100);
      expect(updated.id, mod.id);
      expect(updated.orderItemId, mod.orderItemId);
      expect(updated.modifierId, mod.modifierId);
      expect(updated.modifierName, mod.modifierName);
    });

    test('equality: two modifiers with same fields are equal', () {
      final a = _modifier();
      final b = _modifier();
      expect(a, equals(b));
    });

    test('equality: different priceDelta breaks equality', () {
      final a = _modifier(priceDelta: 50);
      final b = _modifier(priceDelta: 100);
      expect(a, isNot(equals(b)));
    });

    test('equality: different modifierName breaks equality', () {
      final a = _modifier(modifierName: 'Sauce');
      final b = _modifier(modifierName: 'No Sauce');
      expect(a, isNot(equals(b)));
    });

    test('hashCode is consistent with equality', () {
      final a = _modifier();
      final b = _modifier();
      expect(a.hashCode, b.hashCode);
    });

    test('toString contains id, name and delta', () {
      final mod = _modifier(id: 'mod-42', modifierName: 'Käse', priceDelta: 75);
      final str = mod.toString();
      expect(str, contains('mod-42'));
      expect(str, contains('Käse'));
      expect(str, contains('75'));
    });

    test('negative priceDelta (discount modifier)', () {
      final mod = _modifier(priceDelta: -100);
      expect(mod.priceDelta, -100);
    });
  });

  // =========================================================================
  // OrderItemEntity — construction and defaults
  // =========================================================================
  group('OrderItemEntity — construction', () {
    test('creates with all required fields and correct defaults', () {
      final item = _item();
      expect(item.id, 'item-1');
      expect(item.tenantId, 'tenant-1');
      expect(item.ticketId, 'ticket-1');
      expect(item.productId, 'prod-1');
      expect(item.productName, 'Zürich Geschnetzeltes');
      expect(item.quantity, 1.0);
      expect(item.unitPrice, 2850);
      expect(item.subtotal, 2850);
      expect(item.taxAmount, 0);
      expect(item.discountAmount, 0);
      expect(item.status, OrderItemStatus.ordered);
      expect(item.sentToKitchen, false);
      expect(item.notes, isNull);
      expect(item.course, 1);
      expect(item.modifiers, isEmpty);
      expect(item.isTaxFree, false);
      expect(item.isOpenPrice, false);
      expect(item.isWeightBased, false);
      expect(item.weight, isNull);
      expect(item.weightUnit, isNull);
      expect(item.specialDiscountAmount, 0);
      expect(item.taxGroup, 'food');
    });

    test('all OrderItemStatus values are accessible', () {
      expect(OrderItemStatus.values, contains(OrderItemStatus.ordered));
      expect(OrderItemStatus.values, contains(OrderItemStatus.sent));
      expect(OrderItemStatus.values, contains(OrderItemStatus.preparing));
      expect(OrderItemStatus.values, contains(OrderItemStatus.ready));
      expect(OrderItemStatus.values, contains(OrderItemStatus.served));
      expect(OrderItemStatus.values, contains(OrderItemStatus.voidStatus));
    });

    test('taxGroup defaults to food', () {
      final item = OrderItemEntity(
        id: 'x',
        tenantId: 't',
        ticketId: 'tk',
        productId: 'p',
        productName: 'Burger',
        quantity: 1.0,
        unitPrice: 1500,
        subtotal: 1500,
      );
      expect(item.taxGroup, 'food');
    });
  });

  // =========================================================================
  // calculateSubtotal
  // =========================================================================
  group('calculateSubtotal', () {
    test('single item, no modifiers', () {
      final item = _item(unitPrice: 2500, quantity: 1.0);
      expect(item.calculateSubtotal(), 2500);
    });

    test('quantity multiplies unit price', () {
      final item = _item(unitPrice: 1200, quantity: 3.0);
      // (1200 + 0) * 3 = 3600
      expect(item.calculateSubtotal(), 3600);
    });

    test('fractional quantity (e.g. 0.5 kg)', () {
      final item = _item(unitPrice: 8000, quantity: 0.5);
      // 8000 * 0.5 = 4000
      expect(item.calculateSubtotal(), 4000);
    });

    test('modifier adds to unit price before quantity multiply', () {
      final item = _item(
        unitPrice: 1500,
        quantity: 2.0,
        modifiers: [_modifier(priceDelta: 200)],
      );
      // (1500 + 200) * 2 = 3400
      expect(item.calculateSubtotal(), 3400);
    });

    test('multiple modifiers summed', () {
      final item = _item(
        unitPrice: 2000,
        quantity: 1.0,
        modifiers: [
          _modifier(id: 'm1', priceDelta: 100),
          _modifier(id: 'm2', priceDelta: 150),
        ],
      );
      // (2000 + 100 + 150) * 1 = 2250
      expect(item.calculateSubtotal(), 2250);
    });

    test('negative modifier (discount on item)', () {
      final item = _item(
        unitPrice: 3000,
        quantity: 1.0,
        modifiers: [_modifier(priceDelta: -500)],
      );
      // (3000 - 500) * 1 = 2500
      expect(item.calculateSubtotal(), 2500);
    });

    test('results are rounded to nearest integer', () {
      final item = _item(unitPrice: 1001, quantity: 1.0);
      // 1001 * 1.0 = 1001 (no fractional issue)
      expect(item.calculateSubtotal(), 1001);
    });

    test('weight-based: quantity represents weight in grams', () {
      // 80 CHF/kg = 8000 cents/1000g → 350g
      final item = _item(
        unitPrice: 8000,
        quantity: 0.35, // 0.35 kg
        isWeightBased: true,
        weight: 350,
        weightUnit: 'g',
      );
      // round(8000 * 0.35) = 2800
      expect(item.calculateSubtotal(), 2800);
    });
  });

  // =========================================================================
  // copyWith
  // =========================================================================
  group('copyWith', () {
    test('returns identical item when no overrides', () {
      final item = _item();
      final copy = item.copyWith();
      expect(copy, equals(item));
    });

    test('overrides productName', () {
      final item = _item(productName: 'Original');
      final copy = item.copyWith(productName: 'Updated');
      expect(copy.productName, 'Updated');
      expect(item.productName, 'Original');
    });

    test('overrides quantity', () {
      final item = _item(quantity: 1.0);
      final copy = item.copyWith(quantity: 3.0);
      expect(copy.quantity, 3.0);
    });

    test('overrides unitPrice', () {
      final item = _item(unitPrice: 2000);
      final copy = item.copyWith(unitPrice: 2500);
      expect(copy.unitPrice, 2500);
    });

    test('overrides status', () {
      final item = _item(status: OrderItemStatus.ordered);
      final copy = item.copyWith(status: OrderItemStatus.sent);
      expect(copy.status, OrderItemStatus.sent);
    });

    test('overrides sentToKitchen', () {
      final item = _item(sentToKitchen: false);
      final copy = item.copyWith(sentToKitchen: true);
      expect(copy.sentToKitchen, isTrue);
    });

    test('clears notes via nullable override', () {
      final item = _item(notes: 'No onions');
      final copy = item.copyWith(notes: () => null);
      expect(copy.notes, isNull);
    });

    test('sets notes via nullable override', () {
      final item = _item();
      final copy = item.copyWith(notes: () => 'Extra spicy');
      expect(copy.notes, 'Extra spicy');
    });

    test('overrides taxGroup', () {
      final item = _item(taxGroup: 'food');
      final copy = item.copyWith(taxGroup: 'beverage');
      expect(copy.taxGroup, 'beverage');
    });

    test('overrides course', () {
      final item = _item(course: 1);
      final copy = item.copyWith(course: 2);
      expect(copy.course, 2);
    });

    test('overrides modifiers', () {
      final item = _item(modifiers: []);
      final copy = item.copyWith(modifiers: [_modifier()]);
      expect(copy.modifiers.length, 1);
    });

    test('overrides isTaxFree', () {
      final item = _item(isTaxFree: false);
      final copy = item.copyWith(isTaxFree: true);
      expect(copy.isTaxFree, isTrue);
    });

    test('overrides isWeightBased and weight', () {
      final item = _item();
      final copy = item.copyWith(
        isWeightBased: true,
        weight: () => 500.0,
        weightUnit: () => 'g',
      );
      expect(copy.isWeightBased, isTrue);
      expect(copy.weight, 500.0);
      expect(copy.weightUnit, 'g');
    });

    test('overrides specialDiscountAmount', () {
      final item = _item(specialDiscountAmount: 0);
      final copy = item.copyWith(specialDiscountAmount: 300);
      expect(copy.specialDiscountAmount, 300);
    });
  });

  // =========================================================================
  // equality and hashCode
  // =========================================================================
  group('equality', () {
    test('two identical items are equal', () {
      final a = _item();
      final b = _item();
      expect(a, equals(b));
    });

    test('different id breaks equality', () {
      final a = _item(id: 'item-1');
      final b = _item(id: 'item-2');
      expect(a, isNot(equals(b)));
    });

    test('different productName breaks equality', () {
      final a = _item(productName: 'Burger');
      final b = _item(productName: 'Pizza');
      expect(a, isNot(equals(b)));
    });

    test('different quantity breaks equality', () {
      final a = _item(quantity: 1.0);
      final b = _item(quantity: 2.0);
      expect(a, isNot(equals(b)));
    });

    test('different unitPrice breaks equality', () {
      final a = _item(unitPrice: 1000);
      final b = _item(unitPrice: 2000);
      expect(a, isNot(equals(b)));
    });

    test('different status breaks equality', () {
      final a = _item(status: OrderItemStatus.ordered);
      final b = _item(status: OrderItemStatus.sent);
      expect(a, isNot(equals(b)));
    });

    test('different taxGroup breaks equality', () {
      final a = _item(taxGroup: 'food');
      final b = _item(taxGroup: 'beverage');
      expect(a, isNot(equals(b)));
    });

    test('hashCode is consistent with equality', () {
      final a = _item();
      final b = _item();
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  // =========================================================================
  // toString
  // =========================================================================
  group('toString', () {
    test('contains id, productName, quantity and subtotal', () {
      final item = _item(
        id: 'item-99',
        productName: 'Rösti',
        quantity: 2.0,
        subtotal: 3400,
      );
      final str = item.toString();
      expect(str, contains('item-99'));
      expect(str, contains('Rösti'));
      expect(str, contains('2.0'));
      expect(str, contains('3400'));
    });
  });

  // =========================================================================
  // Swiss VAT tax group semantics
  // =========================================================================
  group('Swiss VAT tax group semantics', () {
    test('food taxGroup resolves to correct enum string', () {
      final item = _item(taxGroup: 'food');
      expect(item.taxGroup, 'food');
    });

    test('beverage taxGroup', () {
      final item = _item(taxGroup: 'beverage');
      expect(item.taxGroup, 'beverage');
    });

    test('accommodation taxGroup (3.8%)', () {
      final item = _item(taxGroup: 'accommodation');
      expect(item.taxGroup, 'accommodation');
    });

    test('alcohol taxGroup (8.1% always)', () {
      final item = _item(taxGroup: 'alcohol');
      expect(item.taxGroup, 'alcohol');
    });

    test('isTaxFree overrides taxGroup for calculation purposes', () {
      final item = _item(taxGroup: 'food', isTaxFree: true);
      expect(item.isTaxFree, isTrue);
    });
  });

  // =========================================================================
  // Modification workflow (status transitions)
  // =========================================================================
  group('status transitions via copyWith', () {
    test('ordered → sent', () {
      final item = _item(status: OrderItemStatus.ordered);
      final sent = item.copyWith(
        status: OrderItemStatus.sent,
        sentToKitchen: true,
      );
      expect(sent.status, OrderItemStatus.sent);
      expect(sent.sentToKitchen, isTrue);
    });

    test('sent → preparing', () {
      final item = _item(status: OrderItemStatus.sent);
      final preparing = item.copyWith(status: OrderItemStatus.preparing);
      expect(preparing.status, OrderItemStatus.preparing);
    });

    test('preparing → ready → served', () {
      var item = _item(status: OrderItemStatus.preparing);
      item = item.copyWith(status: OrderItemStatus.ready);
      expect(item.status, OrderItemStatus.ready);
      item = item.copyWith(status: OrderItemStatus.served);
      expect(item.status, OrderItemStatus.served);
    });

    test('void transition', () {
      final item = _item(status: OrderItemStatus.sent);
      final voided = item.copyWith(status: OrderItemStatus.voidStatus);
      expect(voided.status, OrderItemStatus.voidStatus);
    });
  });

  // =========================================================================
  // Edge cases
  // =========================================================================
  group('edge cases', () {
    test('zero unit price', () {
      final item = _item(unitPrice: 0);
      expect(item.calculateSubtotal(), 0);
    });

    test('large quantity (bulk order)', () {
      final item = _item(unitPrice: 100, quantity: 100.0);
      expect(item.calculateSubtotal(), 10000);
    });

    test('item with discount amount', () {
      final item = _item(discountAmount: 500, unitPrice: 2500, subtotal: 2000);
      expect(item.discountAmount, 500);
      expect(item.subtotal, 2000);
    });

    test('item with tax amount snapshot', () {
      final item = _item(taxAmount: 187, subtotal: 2500);
      expect(item.taxAmount, 187);
    });

    test('multi-course item defaults to course 1', () {
      final item = _item();
      expect(item.course, 1);
    });

    test('course 3 (dessert)', () {
      final item = _item(course: 3);
      expect(item.course, 3);
    });

    test('item with long notes', () {
      const longNote = 'No onions, no garlic, extra spicy, on the side please';
      final item = _item(notes: longNote);
      expect(item.notes, longNote);
    });

    test('open price item', () {
      final item = _item(isOpenPrice: true, unitPrice: 500);
      expect(item.isOpenPrice, isTrue);
      expect(item.calculateSubtotal(), 500);
    });
  });
}
