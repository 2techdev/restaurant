import 'package:drift/drift.dart';

/// Per-tenant atomic counter for Swiss fiscal receipt numbers.
///
/// Sequence-number collisions are a compliance risk — two receipts with
/// the same number for the same tenant make the audit chain ambiguous.
/// A dedicated counter table lets the DAO increment inside a single
/// transaction and return the next value, independent of how many
/// concurrent writers issue receipts. Paired with a UNIQUE index on
/// `receipts(tenant_id, receipt_number)` (added in migration v17) the
/// combination gives us "belt and suspenders": the DAO hands out unique
/// numbers; the UNIQUE index is a last-resort guardrail if something
/// bypasses the DAO.
@DataClassName('ReceiptCounter')
class ReceiptCounters extends Table {
  TextColumn get tenantId => text()();

  /// Last issued sequence number for this tenant. Monotonically
  /// increases; next receipt is `current + 1`. Starts at 0 for a fresh
  /// tenant (first issued number is 1).
  IntColumn get current => integer().withDefault(const Constant(0))();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {tenantId};
}
