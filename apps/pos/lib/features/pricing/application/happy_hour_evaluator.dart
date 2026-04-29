/// Pure evaluator that applies a matching [HappyHourRule] to an [OrderItemEntity].
///
/// The evaluator is intentionally side-effect free and takes `now` as a
/// parameter so unit tests don't need to freeze the system clock. The first
/// matching, active rule wins; rules are expected to be ordered by priority
/// by the provider (in practice the pilot only ships one rule, so ordering
/// is not load-bearing yet).
///
/// When a rule matches:
///   * [OrderItemEntity.unitPrice] is reduced by `discountPercent`.
///   * [OrderItemEntity.subtotal] is recalculated from the new unit price,
///     quantity, and existing modifiers — modifier deltas are NOT discounted
///     (matches industry norms: happy-hour discounts the drink, not the
///     "extra lime" upcharge).
///   * A `[HH]` tag is prepended to the notes so the UI / receipt can detect
///     that happy hour was applied without needing a new schema column.
///
/// Notes:
///   * Tax is intentionally NOT recomputed here — the caller
///     (`addItem` in the order provider) already computes tax from the
///     subtotal after this function runs.
///   * Price reduction uses banker-style `.round()` which is consistent with
///     the rest of the cents-based math in [PriceResolver] and [FareEngine].
library;

import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/pricing/domain/happy_hour_rule.dart';

/// Marker prepended to [OrderItemEntity.notes] when happy hour applied.
/// The UI can `startsWith` / `contains` this to render an "HH" chip.
const happyHourNoteTag = '[HH]';

/// Apply the first matching happy-hour rule to [item], returning a new item.
///
/// If no rule matches, the original [item] is returned unchanged.
///
/// Takes [product] so category / name matching stays decoupled from the DB.
/// Takes [now] so tests can pin the clock.
OrderItemEntity applyHappyHour(
  OrderItemEntity item,
  ProductEntity product,
  List<HappyHourRule> rules,
  DateTime now,
) {
  for (final rule in rules) {
    if (!rule.isActiveAt(now)) continue;
    if (!rule.matchesProduct(
      productCategoryId: product.categoryId,
      productName: product.name,
    )) {
      continue;
    }

    final discount = rule.discountPercent.clamp(0, 100);
    if (discount == 0) return item;

    final discountedUnit =
        (item.unitPrice * (100 - discount) / 100).round();

    final modifierTotal =
        item.modifiers.fold<int>(0, (s, m) => s + m.effectiveDelta);
    final newSubtotal =
        ((discountedUnit + modifierTotal) * item.quantity).round();

    final existingNotes = item.notes ?? '';
    final newNotes = existingNotes.contains(happyHourNoteTag)
        ? existingNotes
        : (existingNotes.isEmpty
            ? happyHourNoteTag
            : '$happyHourNoteTag $existingNotes');

    return item.copyWith(
      unitPrice: discountedUnit,
      subtotal: newSubtotal,
      notes: () => newNotes,
    );
  }

  return item;
}
