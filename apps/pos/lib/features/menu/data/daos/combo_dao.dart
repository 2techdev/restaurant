/// DAO for combo / set-menu persistence.
///
/// Combos live in two places:
///   * [Products] row — the PARENT (`isCombo = true`, `comboDiscountCents`
///     optional).
///   * [ComboItems] rows — one per component, keyed by `comboProductId`.
///
/// The DAO hides that split so callers talk in terms of [ComboEntity]
/// / [ComboItemEntity] and never see the companion split. `saveItems`
/// is transactional: it replaces the full component list in one shot
/// so a half-saved combo can never exist.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/database/tables/combo_items.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/combo_entity.dart';

part 'combo_dao.g.dart';

@DriftAccessor(tables: [ComboItems])
class ComboDao extends DatabaseAccessor<AppDatabase> with _$ComboDaoMixin {
  ComboDao(super.db);

  /// Load the full [ComboEntity] for [comboProductId] — parent row merged
  /// with its joined children. Returns `null` when the parent product
  /// does not exist or is not flagged as a combo.
  ///
  /// Joins against [Products] so each item carries the component's
  /// current display name + unit price, so the POS can render the
  /// bundle without a second round trip.
  Future<ComboEntity?> getComboFor(String comboProductId) async {
    final parent = await (select(attachedDatabase.products)
          ..where((t) => t.id.equals(comboProductId)))
        .getSingleOrNull();
    if (parent == null || !parent.isCombo) return null;

    final rows = await (select(comboItems)
          ..where((t) => t.comboProductId.equals(comboProductId))
          ..orderBy([(t) => OrderingTerm(expression: t.displayOrder)]))
        .get();

    final items = <ComboItemEntity>[];
    for (final row in rows) {
      final childProduct = await (select(attachedDatabase.products)
            ..where((t) => t.id.equals(row.itemProductId)))
          .getSingleOrNull();
      items.add(ComboItemEntity(
        id: row.id,
        tenantId: row.tenantId,
        comboProductId: row.comboProductId,
        itemProductId: row.itemProductId,
        itemProductName: childProduct?.name,
        itemUnitPrice: childProduct?.price,
        quantity: row.quantity,
        groupName: row.groupName,
        isRequired: row.isRequired,
        canSubstitute: row.canSubstitute,
        displayOrder: row.displayOrder,
      ));
    }

    return ComboEntity(
      comboProductId: comboProductId,
      items: items,
      discountCents: parent.comboDiscountCents,
    );
  }

  /// Replace the component list for [comboProductId] in one transaction.
  ///
  /// All existing rows for that parent are deleted, then the supplied
  /// [items] are inserted. The caller is responsible for setting
  /// `isCombo = true` on the parent product row separately (the parent
  /// lives on the [Products] table, not [ComboItems]).
  Future<void> saveItems(
    String comboProductId,
    List<ComboItemEntity> items,
  ) async {
    await transaction(() async {
      await (delete(comboItems)
            ..where((t) => t.comboProductId.equals(comboProductId)))
          .go();

      final now = DateTime.now();
      for (final item in items) {
        await into(comboItems).insert(ComboItemsCompanion.insert(
          id: item.id,
          tenantId: item.tenantId,
          comboProductId: comboProductId,
          itemProductId: item.itemProductId,
          quantity: Value(item.quantity),
          groupName: Value(item.groupName),
          isRequired: Value(item.isRequired),
          canSubstitute: Value(item.canSubstitute),
          displayOrder: Value(item.displayOrder),
          createdAt: now,
          updatedAt: now,
        ));
      }
    });
  }

  /// Remove every component row for a combo. Called when a product is
  /// demoted from combo (`isCombo = false`) or hard-deleted. Does not
  /// touch the parent product row.
  Future<int> clearItems(String comboProductId) {
    return (delete(comboItems)
          ..where((t) => t.comboProductId.equals(comboProductId)))
        .go();
  }

  /// Count the components of a combo without loading them.
  Future<int> countItems(String comboProductId) async {
    final countExpr = comboItems.id.count();
    final query = selectOnly(comboItems)
      ..addColumns([countExpr])
      ..where(comboItems.comboProductId.equals(comboProductId));
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }
}
