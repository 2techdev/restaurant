/// Extended kiosk tests: KioskSessionNotifier full flow, KioskSessionState
/// derived values, and KioskOrderService full submit → kitchen dispatch path.
///
/// Run with:
///   flutter test test/features/kiosk/kiosk_session_extended_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/kitchen/data/repositories/kitchen_repository_impl.dart';
import 'package:gastrocore_pos/features/kiosk/domain/kiosk_cart_item.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/providers/kiosk_provider.dart';
import 'package:gastrocore_pos/features/kiosk/services/kiosk_order_service.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-kiosk-ext';
const _deviceId = 'KIOSK-DEV-EXT-01';

ProductEntity _makeProduct({
  String? id,
  String name = 'Brezel',
  int price = 500,
  String taxGroup = 'food',
}) {
  return ProductEntity(
    id: id ?? IdGenerator.generateId(),
    tenantId: _tenantId,
    categoryId: 'cat-snacks',
    name: name,
    price: price,
    costPrice: 150,
    taxGroup: taxGroup,
    isActive: true,
    displayOrder: 0,
    printerGroup: 'kitchen',
  );
}

OrderItemModifierEntity _makeModifier({
  String name = 'Mit Butter',
  int priceDelta = 100,
}) {
  final id = IdGenerator.generateId();
  return OrderItemModifierEntity(
    id: id,
    orderItemId: 'placeholder',
    modifierId: 'mod-${id.substring(0, 6)}',
    modifierName: name,
    priceDelta: priceDelta,
  );
}

KioskCartItem _makeCartItem({
  ProductEntity? product,
  int quantity = 1,
  List<OrderItemModifierEntity> modifiers = const [],
}) {
  return KioskCartItem(
    id: IdGenerator.generateId(),
    product: product ?? _makeProduct(),
    quantity: quantity,
    modifiers: modifiers,
  );
}

// ---------------------------------------------------------------------------
// KioskCartItem unit tests
// ---------------------------------------------------------------------------

void main() {
  group('KioskCartItem — price helpers', () {
    test('unitPrice = product.price when no modifiers', () {
      final product = _makeProduct(price: 800);
      final item = _makeCartItem(product: product);
      expect(item.unitPrice, equals(800));
    });

    test('unitPrice includes modifier deltas', () {
      final product = _makeProduct(price: 800);
      final modifier = _makeModifier(priceDelta: 150);
      final item = _makeCartItem(product: product, modifiers: [modifier]);
      expect(item.unitPrice, equals(950)); // 800 + 150
    });

    test('subtotal = unitPrice × quantity', () {
      final product = _makeProduct(price: 1000);
      final item = _makeCartItem(product: product, quantity: 3);
      expect(item.subtotal, equals(3000));
    });

    test('subtotal with modifier and quantity', () {
      final product = _makeProduct(price: 500);
      final modifier = _makeModifier(priceDelta: 200);
      final item = _makeCartItem(product: product, quantity: 2, modifiers: [modifier]);
      expect(item.subtotal, equals(1400)); // (500+200)*2
    });

    test('copyWith preserves id and overrides product', () {
      final original = _makeCartItem();
      final newProduct = _makeProduct(name: 'New');
      final copy = original.copyWith(product: newProduct);
      expect(copy.id, equals(original.id));
      expect(copy.product.name, equals('New'));
    });

    test('equality is by id only', () {
      final a = _makeCartItem();
      final b = a.copyWith(quantity: 5);
      expect(a, equals(b)); // same id → equal
    });
  });

  // =========================================================================
  // KioskSessionState — derived totals
  // =========================================================================

  group('KioskSessionState — derived totals', () {
    test('empty cart has subtotal 0 and itemCount 0', () {
      const s = KioskSessionState();
      expect(s.subtotal, equals(0));
      expect(s.itemCount, equals(0));
      expect(s.isEmpty, isTrue);
    });

    test('subtotal sums all item subtotals', () {
      final items = [
        _makeCartItem(product: _makeProduct(price: 300), quantity: 2),
        _makeCartItem(product: _makeProduct(price: 500), quantity: 1),
      ];
      final s = KioskSessionState(items: items);
      expect(s.subtotal, equals(1100)); // 600 + 500
    });

    test('itemCount sums item quantities', () {
      final items = [
        _makeCartItem(quantity: 3),
        _makeCartItem(quantity: 2),
      ];
      final s = KioskSessionState(items: items);
      expect(s.itemCount, equals(5));
    });

    test('isEmpty is false when cart has items', () {
      final s = KioskSessionState(items: [_makeCartItem()]);
      expect(s.isEmpty, isFalse);
    });

    test('copyWith overrides order type', () {
      const s = KioskSessionState(orderType: OrderType.dineIn);
      final updated = s.copyWith(orderType: OrderType.takeaway);
      expect(updated.orderType, equals(OrderType.takeaway));
      expect(updated.items, isEmpty);
    });

    test('copyWith can clear confirmedOrderNumber', () {
      final s = KioskSessionState(
        confirmedOrderNumber: '0042',
      );
      final cleared = s.copyWith(confirmedOrderNumber: () => null);
      expect(cleared.confirmedOrderNumber, isNull);
    });
  });

  // =========================================================================
  // KioskSessionNotifier
  // =========================================================================

  group('KioskSessionNotifier', () {
    late KioskSessionNotifier notifier;

    setUp(() {
      notifier = KioskSessionNotifier();
    });

    test('initial state is empty dine-in', () {
      expect(notifier.state.isEmpty, isTrue);
      expect(notifier.state.orderType, equals(OrderType.dineIn));
    });

    test('addItem adds new product to cart', () {
      final product = _makeProduct(name: 'Kaffee');
      notifier.addItem(product);
      expect(notifier.state.items.length, equals(1));
      expect(notifier.state.items.first.product.name, equals('Kaffee'));
    });

    test('addItem increments quantity for same product+modifiers', () {
      final product = _makeProduct();
      notifier.addItem(product);
      notifier.addItem(product);
      expect(notifier.state.items.length, equals(1));
      expect(notifier.state.items.first.quantity, equals(2));
    });

    test('addItem creates new entry for same product with different modifiers', () {
      final product = _makeProduct();
      final mod1 = _makeModifier(name: 'Mit Butter');
      final mod2 = _makeModifier(name: 'Ohne Salz');
      notifier.addItem(product, modifiers: [mod1]);
      notifier.addItem(product, modifiers: [mod2]);
      expect(notifier.state.items.length, equals(2));
    });

    test('setQuantity updates the item quantity', () {
      final product = _makeProduct();
      notifier.addItem(product);
      final itemId = notifier.state.items.first.id;
      notifier.setQuantity(itemId, 5);
      expect(notifier.state.items.first.quantity, equals(5));
    });

    test('setQuantity with 0 removes the item', () {
      final product = _makeProduct();
      notifier.addItem(product);
      final itemId = notifier.state.items.first.id;
      notifier.setQuantity(itemId, 0);
      expect(notifier.state.items, isEmpty);
    });

    test('removeItem removes a specific item', () {
      final p1 = _makeProduct(id: IdGenerator.generateId(), name: 'A');
      final p2 = _makeProduct(id: IdGenerator.generateId(), name: 'B');
      notifier.addItem(p1);
      notifier.addItem(p2);
      final firstId = notifier.state.items.first.id;
      notifier.removeItem(firstId);
      expect(notifier.state.items.length, equals(1));
      expect(notifier.state.items.first.product.name, equals('B'));
    });

    test('clearCart empties the cart', () {
      notifier.addItem(_makeProduct());
      notifier.addItem(_makeProduct());
      notifier.clearCart();
      expect(notifier.state.isEmpty, isTrue);
    });

    test('setOrderType changes the order type', () {
      notifier.setOrderType(OrderType.takeaway);
      expect(notifier.state.orderType, equals(OrderType.takeaway));
    });

    test('setConfirmedOrder sets the confirmed order number', () {
      notifier.setConfirmedOrder('0099');
      expect(notifier.state.confirmedOrderNumber, equals('0099'));
    });

    test('reset returns to initial state', () {
      notifier.addItem(_makeProduct());
      notifier.setOrderType(OrderType.takeaway);
      notifier.setConfirmedOrder('0001');
      notifier.reset();
      expect(notifier.state.isEmpty, isTrue);
      expect(notifier.state.orderType, equals(OrderType.dineIn));
      expect(notifier.state.confirmedOrderNumber, isNull);
    });

    test('subtotal updates as items are added', () {
      final p = _makeProduct(price: 400);
      notifier.addItem(p, quantity: 3);
      expect(notifier.state.subtotal, equals(1200));
      notifier.clearCart();
      expect(notifier.state.subtotal, equals(0));
    });
  });

  // =========================================================================
  // KioskOrderService — full submitOrder flow
  // =========================================================================

  group('KioskOrderService — submitOrder', () {
    late AppDatabase db;
    late KioskOrderService svc;

    setUp(() {
      db = AppDatabase.createInMemory();
      svc = KioskOrderService(
        orderRepo: OrderRepositoryImpl(db),
        kitchenRepo: KitchenRepositoryImpl(db),
      );
    });

    tearDown(() async => db.close());

    test('returns order number string on success', () async {
      final product = _makeProduct(price: 1200);
      final cartItem = _makeCartItem(product: product);

      final orderNum = await svc.submitOrder(
        tenantId: _tenantId,
        deviceId: _deviceId,
        items: [cartItem],
        orderType: OrderType.dineIn,
      );

      expect(orderNum, isNotEmpty);
    });

    test('creates ticket with kiosk channel and sent status', () async {
      final product = _makeProduct(price: 900);
      final cartItem = _makeCartItem(product: product);

      await svc.submitOrder(
        tenantId: _tenantId,
        deviceId: _deviceId,
        items: [cartItem],
        orderType: OrderType.dineIn,
      );

      final repo = OrderRepositoryImpl(db);
      await repo.getOpenTickets(_tenantId);
      // Status is 'sent' so it may be in history — check DB directly.
      final rows = await db.select(db.tickets).get();
      expect(rows.length, equals(1));
      expect(rows.first.channel, equals(OrderChannel.kiosk.name));
      expect(rows.first.status, equals(TicketStatus.sent.name));
    });

    test('creates kitchen ticket for kiosk order', () async {
      final product = _makeProduct(price: 1500);
      final cartItem = _makeCartItem(product: product);

      await svc.submitOrder(
        tenantId: _tenantId,
        deviceId: _deviceId,
        items: [cartItem],
        orderType: OrderType.dineIn,
      );

      final kitchenRows = await db.select(db.kitchenTickets).get();
      expect(kitchenRows.length, equals(1));
      expect(kitchenRows.first.waiterName, equals('Kiosk'));
    });

    test('submits multiple items correctly', () async {
      final p1 = _makeProduct(name: 'Bier', price: 800, taxGroup: 'beverage');
      final p2 = _makeProduct(name: 'Wasser', price: 300, taxGroup: 'beverage');
      final items = [
        _makeCartItem(product: p1, quantity: 2),
        _makeCartItem(product: p2, quantity: 1),
      ];

      final orderNum = await svc.submitOrder(
        tenantId: _tenantId,
        deviceId: _deviceId,
        items: items,
        orderType: OrderType.dineIn,
      );

      expect(orderNum, isNotEmpty);

      final rows = await db.select(db.tickets).get();
      expect(rows.first.subtotal, equals(1900)); // 2×800 + 1×300
    });

    test('applies 8.1% VAT to food items (dine-in)', () async {
      final product = _makeProduct(price: 1000, taxGroup: 'food');
      final cartItem = _makeCartItem(product: product);

      await svc.submitOrder(
        tenantId: _tenantId,
        deviceId: _deviceId,
        items: [cartItem],
        orderType: OrderType.dineIn,
      );

      final itemRows = await db.select(db.orderItems).get();
      // 1000 * 8.1 / 108.1 = 74.93 → 75
      expect(itemRows.first.taxAmount, equals(75));
    });

    test('applies 2.6% VAT to food items (takeaway)', () async {
      final product = _makeProduct(price: 1000, taxGroup: 'food');
      final cartItem = _makeCartItem(product: product);

      await svc.submitOrder(
        tenantId: _tenantId,
        deviceId: _deviceId,
        items: [cartItem],
        orderType: OrderType.takeaway,
      );

      final itemRows = await db.select(db.orderItems).get();
      // 1000 * 2.6 / 102.6 = 25.34 → 25
      expect(itemRows.first.taxAmount, equals(25));
    });

    test('consecutive submissions generate unique order numbers', () async {
      final product = _makeProduct(price: 500);
      final cartItem = _makeCartItem(product: product);

      final n1 = await svc.submitOrder(
        tenantId: _tenantId,
        deviceId: _deviceId,
        items: [_makeCartItem(product: product)],
        orderType: OrderType.dineIn,
      );
      final n2 = await svc.submitOrder(
        tenantId: _tenantId,
        deviceId: _deviceId,
        items: [cartItem],
        orderType: OrderType.dineIn,
      );

      expect(n1, isNot(equals(n2)));
    });

    test('5-Rappen rounding rounds to nearest 5', () {
      expect(KioskOrderService.roundToFiveRappen(1231), equals(1230));
      expect(KioskOrderService.roundToFiveRappen(1233), equals(1235));
      expect(KioskOrderService.roundToFiveRappen(1235), equals(1235));
      expect(KioskOrderService.roundToFiveRappen(1237), equals(1235));
      expect(KioskOrderService.roundToFiveRappen(1238), equals(1240));
    });
  });
}
