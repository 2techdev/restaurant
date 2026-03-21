/// Applies remote sync events to the local SQLite database.
///
/// Strategy: **last-write-wins** via SQL `INSERT OR REPLACE` / soft-delete.
///
/// Each [apply] call receives a table name, an operation, and a JSON payload
/// that mirrors the row's column values. Because the payload originates from
/// the same Drift schema used on every device the column names are stable.
///
/// Supported operations:
///   - `insert` / `update` → upsert (INSERT OR REPLACE) the payload row.
///   - `delete`            → soft-delete: set `is_deleted = 1`.
///
/// Tables that are allowed to receive remote upserts are declared in
/// [_allowedTables]. Any unknown table name is silently skipped so a
/// schema-mismatched server cannot corrupt unrelated state.
library;

import 'package:drift/drift.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';

/// Responsible for writing a pulled [RemotePayload] into the correct table.
class RemoteEventApplier {
  RemoteEventApplier(this._db);

  final AppDatabase _db;

  /// Tables that may be modified by remote events.
  static const _allowedTables = {
    'products',
    'categories',
    'modifier_groups',
    'modifiers',
    'product_modifier_groups',
    'product_prices',
    'product_specifications',
    'combo_items',
    'floors',
    'restaurant_tables',
    'tickets',
    'order_items',
    'order_item_modifiers',
    'kitchen_tickets',
    'kitchen_ticket_items',
    'bills',
    'payments',
    'shifts',
    'cash_movements',
    'receipts',
    'tax_profiles',
    'order_type_rules',
    'users',
  };

  /// Apply a single remote event to the local database.
  ///
  /// [tableName] is the Drift table name (snake_case, matches the SQL table).
  /// [operation] is `'insert'`, `'update'`, or `'delete'`.
  /// [recordId]  is the primary key UUID string.
  /// [payload]   is a `Map<String, dynamic>` from the remote JSON.
  Future<void> apply({
    required String tableName,
    required String operation,
    required String recordId,
    required Map<String, dynamic> payload,
  }) async {
    if (!_allowedTables.contains(tableName)) return;

    if (operation == 'delete') {
      await _softDelete(tableName, recordId);
    } else {
      await _upsert(tableName, payload);
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Upsert [payload] into [tableName] using INSERT OR REPLACE.
  ///
  /// The payload must include the `id` column. Any extra keys not present in
  /// the actual table are silently ignored by SQLite.
  Future<void> _upsert(
    String tableName,
    Map<String, dynamic> payload,
  ) async {
    if (payload.isEmpty) return;

    // Stamp sync_status so local watchers know this row is "clean".
    final row = {...payload, 'sync_status': 'synced'};

    final columns = row.keys.join(', ');
    final placeholders = List.filled(row.length, '?').join(', ');

    await _db.customStatement(
      'INSERT OR REPLACE INTO $tableName ($columns) VALUES ($placeholders)',
      row.values.map(_toSqlValue).toList(),
    );
  }

  /// Mark [recordId] as deleted without removing the row so offline clients
  /// that haven't synced yet can still see the tombstone.
  Future<void> _softDelete(String tableName, String recordId) async {
    await _db.customStatement(
      'UPDATE $tableName SET is_deleted = 1, sync_status = ? WHERE id = ?',
      ['synced', recordId],
    );
  }

  /// Convert a Dart value to a type SQLite accepts via Drift's statement API.
  ///
  /// - [DateTime] → ISO-8601 string (matches Drift's default text encoding).
  /// - [bool]     → 0 / 1 integer.
  /// - Everything else is passed through (int, double, String, null).
  static Object? _toSqlValue(Object? value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is bool) return value ? 1 : 0;
    return value;
  }
}
