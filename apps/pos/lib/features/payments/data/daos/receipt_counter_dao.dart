/// Atomic per-tenant counter for Swiss fiscal receipt numbers.
///
/// Every call to [nextReceiptNumber] runs inside a single Drift
/// transaction that (a) upserts the counter row, (b) increments the
/// `current` column by 1, and (c) returns the freshly issued value.
/// SQLite serialises writes inside a transaction, so two concurrent
/// callers cannot see the same `current` value — the second waits for
/// the first to commit.
///
/// Paired with the UNIQUE partial index on
/// `receipts(tenant_id, receipt_number) WHERE is_deleted = 0` added in
/// migration v17, this gives "belt and suspenders" protection against
/// duplicate receipt numbers (a Swiss audit red flag).
library;

import 'package:drift/drift.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/database/tables/receipt_counters.dart';

part 'receipt_counter_dao.g.dart';

@DriftAccessor(tables: [ReceiptCounters])
class ReceiptCounterDao extends DatabaseAccessor<AppDatabase>
    with _$ReceiptCounterDaoMixin {
  ReceiptCounterDao(super.db);

  /// Atomically reserve the next receipt sequence number for [tenantId].
  ///
  /// Returns a monotonically increasing integer starting at 1 for the
  /// tenant's first receipt. Safe to call concurrently — callers that
  /// overlap are serialised by the SQLite transaction.
  Future<int> nextReceiptNumber(String tenantId) async {
    return transaction(() async {
      final existing = await (select(receiptCounters)
            ..where((t) => t.tenantId.equals(tenantId)))
          .getSingleOrNull();

      final nextValue = (existing?.current ?? 0) + 1;
      final now = DateTime.now();

      await into(receiptCounters).insertOnConflictUpdate(
        ReceiptCountersCompanion(
          tenantId: Value(tenantId),
          current: Value(nextValue),
          updatedAt: Value(now),
        ),
      );

      return nextValue;
    });
  }

  /// Current last-issued value for [tenantId]. Returns 0 when the tenant
  /// has never issued a receipt.
  Future<int> peekCurrent(String tenantId) async {
    final row = await (select(receiptCounters)
          ..where((t) => t.tenantId.equals(tenantId)))
        .getSingleOrNull();
    return row?.current ?? 0;
  }
}
