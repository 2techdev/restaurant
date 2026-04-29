/// Tests for [ComboDao] and the combo pricing helper on [ComboEntity].
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/combo_entity.dart';

const _tenant = 't-combo';

Future<void> _seedProduct(
  AppDatabase db, {
  required String id,
  required String name,
  required int price,
  bool isCombo = false,
  int? comboDiscountCents,
}) async {
  await db.into(db.products).insert(ProductsCompanion.insert(
        id: id,
        tenantId: _tenant,
        categoryId: 'cat-1',
        name: name,
        price: price,
        isActive: const Value(true),
        isCombo: Value(isCombo),
        comboDiscountCents: Value(comboDiscountCents),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

void main() {
  group('ComboDao', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('getComboFor returns null when parent is not flagged as combo',
        () async {
      await _seedProduct(db, id: 'p1', name: 'Plain burger', price: 1200);
      final combo = await db.comboDao.getComboFor('p1');
      expect(combo, isNull);
    });

    test('getComboFor joins component name + unit price from Products',
        () async {
      await _seedProduct(db,
          id: 'menu-1',
          name: 'Menu 1',
          price: 2500,
          isCombo: true,
          comboDiscountCents: 300);
      await _seedProduct(db, id: 'burger', name: 'Burger', price: 1500);
      await _seedProduct(db, id: 'fries', name: 'Fries', price: 500);
      await _seedProduct(db, id: 'cola', name: 'Cola', price: 400);

      await db.comboDao.saveItems('menu-1', [
        ComboItemEntity(
          id: 'ci-1',
          tenantId: _tenant,
          comboProductId: 'menu-1',
          itemProductId: 'burger',
          displayOrder: 0,
        ),
        ComboItemEntity(
          id: 'ci-2',
          tenantId: _tenant,
          comboProductId: 'menu-1',
          itemProductId: 'fries',
          displayOrder: 1,
        ),
        ComboItemEntity(
          id: 'ci-3',
          tenantId: _tenant,
          comboProductId: 'menu-1',
          itemProductId: 'cola',
          quantity: 2, // two drinks in one combo
          displayOrder: 2,
        ),
      ]);

      final combo = await db.comboDao.getComboFor('menu-1');
      expect(combo, isNotNull);
      expect(combo!.items.length, 3);
      expect(combo.items[0].itemProductName, 'Burger');
      expect(combo.items[0].itemUnitPrice, 1500);
      expect(combo.items[2].itemProductName, 'Cola');
      expect(combo.items[2].quantity, 2);
      expect(combo.discountCents, 300);
    });

    test('saveItems replaces the full component list on each call', () async {
      await _seedProduct(db,
          id: 'menu-2', name: 'Menu 2', price: 1000, isCombo: true);
      await _seedProduct(db, id: 'a', name: 'A', price: 500);
      await _seedProduct(db, id: 'b', name: 'B', price: 600);
      await _seedProduct(db, id: 'c', name: 'C', price: 700);

      await db.comboDao.saveItems('menu-2', [
        ComboItemEntity(
          id: 'x1',
          tenantId: _tenant,
          comboProductId: 'menu-2',
          itemProductId: 'a',
        ),
        ComboItemEntity(
          id: 'x2',
          tenantId: _tenant,
          comboProductId: 'menu-2',
          itemProductId: 'b',
        ),
      ]);
      expect(await db.comboDao.countItems('menu-2'), 2);

      // Replace with a single different child — the two prior rows must
      // be wiped by the transactional save.
      await db.comboDao.saveItems('menu-2', [
        ComboItemEntity(
          id: 'x3',
          tenantId: _tenant,
          comboProductId: 'menu-2',
          itemProductId: 'c',
        ),
      ]);
      expect(await db.comboDao.countItems('menu-2'), 1);

      final combo = await db.comboDao.getComboFor('menu-2');
      expect(combo!.items.single.itemProductName, 'C');
    });

    test('clearItems removes every component row for a combo', () async {
      await _seedProduct(db,
          id: 'menu-3', name: 'Menu 3', price: 900, isCombo: true);
      await _seedProduct(db, id: 'a', name: 'A', price: 500);
      await db.comboDao.saveItems('menu-3', [
        ComboItemEntity(
          id: 'ci-a',
          tenantId: _tenant,
          comboProductId: 'menu-3',
          itemProductId: 'a',
        ),
      ]);
      expect(await db.comboDao.countItems('menu-3'), 1);

      final removed = await db.comboDao.clearItems('menu-3');
      expect(removed, 1);
      expect(await db.comboDao.countItems('menu-3'), 0);
    });
  });

  group('ComboEntity.priceCents', () {
    test('fixed mode returns the parent price even when items are expensive',
        () {
      final combo = ComboEntity(
        comboProductId: 'p',
        items: [
          const ComboItemEntity(
            id: 'i',
            tenantId: _tenant,
            comboProductId: 'p',
            itemProductId: 'x',
            itemUnitPrice: 5000,
          ),
        ],
        // discountCents = null  →  fixed price mode
      );
      expect(combo.mode, ComboPricingMode.fixed);
      expect(combo.priceCents(fixedPrice: 1990), 1990);
    });

    test('sumMinusDiscount subtracts discount from component total', () {
      final combo = ComboEntity(
        comboProductId: 'p',
        discountCents: 200,
        items: const [
          ComboItemEntity(
            id: 'a',
            tenantId: _tenant,
            comboProductId: 'p',
            itemProductId: 'x',
            itemUnitPrice: 1500,
          ),
          ComboItemEntity(
            id: 'b',
            tenantId: _tenant,
            comboProductId: 'p',
            itemProductId: 'y',
            itemUnitPrice: 500,
            quantity: 2, // 500 * 2 = 1000
          ),
        ],
      );
      expect(combo.mode, ComboPricingMode.sumMinusDiscount);
      // 1500 + 1000 - 200 = 2300
      expect(combo.priceCents(fixedPrice: 9999), 2300);
    });

    test('sumMinusDiscount floors at zero when discount exceeds sum', () {
      final combo = ComboEntity(
        comboProductId: 'p',
        discountCents: 99999,
        items: const [
          ComboItemEntity(
            id: 'a',
            tenantId: _tenant,
            comboProductId: 'p',
            itemProductId: 'x',
            itemUnitPrice: 100,
          ),
        ],
      );
      expect(combo.priceCents(fixedPrice: 500), 0);
    });
  });
}
