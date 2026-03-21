/// Unit tests for [KioskSessionNotifier] — pure state logic, no database.
///
/// Run with:
///   flutter test test/features/kiosk/kiosk_session_notifier_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/kiosk/domain/kiosk_cart_item.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/providers/kiosk_provider.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProductEntity _product({
  String id = 'p1',
  String name = 'Test Product',
  int price = 1000,
  String taxGroup = 'food',
}) {
  return ProductEntity(
    id: id,
    tenantId: 'tenant-1',
    categoryId: 'cat-1',
    name: name,
    price: price,
    costPrice: 0,
    taxGroup: taxGroup,
    isActive: true,
    displayOrder: 0,
    printerGroup: 'kitchen',
  );
}

KioskSessionNotifier _notifier() => KioskSessionNotifier();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('KioskSessionNotifier — initial state', () {
    test('cart is empty on init', () {
      final n = _notifier();
      expect(n.state.isEmpty, isTrue);
      expect(n.state.items, isEmpty);
      expect(n.state.subtotal, equals(0));
      expect(n.state.itemCount, equals(0));
    });

    test('default order type is dineIn', () {
      final n = _notifier();
      expect(n.state.orderType, equals(OrderType.dineIn));
    });
  });

  group('KioskSessionNotifier — addItem', () {
    test('adds a new product to cart', () {
      final n = _notifier();
      final p = _product(price: 1500);

      n.addItem(p, quantity: 1);

      expect(n.state.items.length, equals(1));
      expect(n.state.items.first.product.id, equals(p.id));
      expect(n.state.items.first.quantity, equals(1));
    });

    test('increments quantity when same product+modifiers added again', () {
      final n = _notifier();
      final p = _product();

      n.addItem(p, quantity: 1);
      n.addItem(p, quantity: 2);

      expect(n.state.items.length, equals(1));
      expect(n.state.items.first.quantity, equals(3));
    });

    test('different products create separate cart lines', () {
      final n = _notifier();
      n.addItem(_product(id: 'p1'), quantity: 1);
      n.addItem(_product(id: 'p2'), quantity: 1);

      expect(n.state.items.length, equals(2));
    });

    test('subtotal is sum of item subtotals', () {
      final n = _notifier();
      n.addItem(_product(price: 500), quantity: 2);
      n.addItem(_product(id: 'p2', price: 300), quantity: 1);

      expect(n.state.subtotal, equals(1300)); // 500×2 + 300×1
    });

    test('itemCount is sum of quantities', () {
      final n = _notifier();
      n.addItem(_product(), quantity: 3);
      n.addItem(_product(id: 'p2'), quantity: 2);

      expect(n.state.itemCount, equals(5));
    });
  });

  group('KioskSessionNotifier — setQuantity', () {
    test('updates quantity of existing item', () {
      final n = _notifier();
      n.addItem(_product());
      final id = n.state.items.first.id;

      n.setQuantity(id, 5);

      expect(n.state.items.first.quantity, equals(5));
    });

    test('setQuantity(0) removes the item', () {
      final n = _notifier();
      n.addItem(_product());
      final id = n.state.items.first.id;

      n.setQuantity(id, 0);

      expect(n.state.items, isEmpty);
    });

    test('setQuantity(-1) removes the item', () {
      final n = _notifier();
      n.addItem(_product());
      final id = n.state.items.first.id;

      n.setQuantity(id, -1);

      expect(n.state.items, isEmpty);
    });
  });

  group('KioskSessionNotifier — removeItem', () {
    test('removes item by id', () {
      final n = _notifier();
      n.addItem(_product(id: 'p1'));
      n.addItem(_product(id: 'p2'));
      final id = n.state.items.first.id;

      n.removeItem(id);

      expect(n.state.items.length, equals(1));
    });

    test('no-op when id not found', () {
      final n = _notifier();
      n.addItem(_product());

      n.removeItem('nonexistent-id');

      expect(n.state.items.length, equals(1));
    });
  });

  group('KioskSessionNotifier — clearCart', () {
    test('empties the cart', () {
      final n = _notifier();
      n.addItem(_product());
      n.addItem(_product(id: 'p2'));

      n.clearCart();

      expect(n.state.items, isEmpty);
    });
  });

  group('KioskSessionNotifier — setOrderType', () {
    test('switches to takeaway', () {
      final n = _notifier();
      n.setOrderType(OrderType.takeaway);
      expect(n.state.orderType, equals(OrderType.takeaway));
    });

    test('switches back to dineIn', () {
      final n = _notifier();
      n.setOrderType(OrderType.takeaway);
      n.setOrderType(OrderType.dineIn);
      expect(n.state.orderType, equals(OrderType.dineIn));
    });
  });

  group('KioskSessionNotifier — setConfirmedOrder', () {
    test('stores confirmed order number', () {
      final n = _notifier();
      n.setConfirmedOrder('0042');
      expect(n.state.confirmedOrderNumber, equals('0042'));
    });
  });

  group('KioskSessionNotifier — reset', () {
    test('resets all state to initial', () {
      final n = _notifier();
      n.addItem(_product());
      n.setOrderType(OrderType.takeaway);
      n.setConfirmedOrder('0001');

      n.reset();

      expect(n.state.items, isEmpty);
      expect(n.state.orderType, equals(OrderType.dineIn));
      expect(n.state.confirmedOrderNumber, isNull);
    });
  });

  group('KioskCartItem', () {
    test('subtotal = unitPrice × quantity with no modifiers', () {
      final item = KioskCartItem(
        id: 'i1',
        product: _product(price: 800),
        quantity: 3,
      );
      expect(item.subtotal, equals(2400));
    });

    test('unitPrice includes positive modifier delta', () {
      final item = KioskCartItem(
        id: 'i1',
        product: _product(price: 1000),
        quantity: 1,
        modifiers: [
          OrderItemModifierEntity(
            id: 'm1',
            orderItemId: 'i1',
            modifierId: 'mod-1',
            modifierName: 'Extra Cheese',
            priceDelta: 150,
          ),
        ],
      );
      expect(item.unitPrice, equals(1150));
      expect(item.subtotal, equals(1150));
    });

    test('unitPrice includes negative modifier delta', () {
      final item = KioskCartItem(
        id: 'i1',
        product: _product(price: 1000),
        quantity: 2,
        modifiers: [
          OrderItemModifierEntity(
            id: 'm2',
            orderItemId: 'i1',
            modifierId: 'mod-2',
            modifierName: 'Small size',
            priceDelta: -200,
          ),
        ],
      );
      expect(item.unitPrice, equals(800));
      expect(item.subtotal, equals(1600)); // 800 × 2
    });

    test('equality is based on id', () {
      final p = _product();
      final a = KioskCartItem(id: 'same', product: p, quantity: 1);
      final b = KioskCartItem(id: 'same', product: p, quantity: 99);
      expect(a, equals(b)); // id-based equality
    });
  });
}
