/// Drift-backed implementation of the kitchen repository.
///
/// Reads and writes [KitchenTicket] and [KitchenTicketItem] rows.
/// Exposes reactive streams so the KDS screen auto-updates when
/// tickets are created or completed.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/kitchen/domain/entities/kitchen_ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';

class KitchenRepositoryImpl {
  final AppDatabase _db;

  KitchenRepositoryImpl(this._db);

  // =========================================================================
  // Streams
  // =========================================================================

  /// Stream of active kitchen tickets (status: pending or preparing),
  /// ordered oldest-first so the most urgent ticket is top-left.
  ///
  /// The stream re-emits whenever any [KitchenTickets] row changes — e.g.
  /// when a new ticket is created or a ticket is bumped to 'served'.
  Stream<List<KitchenTicketEntity>> watchActiveTickets() {
    return (_db.select(_db.kitchenTickets)
          ..where(
            (t) =>
                t.status.isIn(['pending', 'preparing']) &
                t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.sentAt)]))
        .watch()
        .asyncMap((rows) async {
      if (rows.isEmpty) return const <KitchenTicketEntity>[];

      // Batch-load all items for the current active tickets.
      final ids = rows.map((r) => r.id).toList();
      final itemRows = await (_db.select(_db.kitchenTicketItems)
            ..where((i) => i.kitchenTicketId.isIn(ids))
            ..orderBy([(i) => OrderingTerm.asc(i.createdAt)]))
          .get();

      // Group items by kitchen ticket id.
      final byTicket = <String, List<KitchenTicketItem>>{};
      for (final item in itemRows) {
        byTicket.putIfAbsent(item.kitchenTicketId, () => []).add(item);
      }

      return rows.map((row) {
        final items = byTicket[row.id] ?? const [];
        return _toEntity(row, items);
      }).toList();
    });
  }

  /// Stream of how many tickets were completed (status: 'served') today.
  Stream<int> watchCompletedTodayCount(String tenantId) {
    final startOfDay = _startOfToday();
    final idCol = _db.kitchenTickets.id;
    final countExpr = idCol.count();

    return (_db.selectOnly(_db.kitchenTickets)
          ..addColumns([countExpr])
          ..where(
            _db.kitchenTickets.tenantId.equals(tenantId) &
                _db.kitchenTickets.status.equals('served') &
                _db.kitchenTickets.isDeleted.equals(false) &
                _db.kitchenTickets.completedAt
                    .isBiggerOrEqualValue(startOfDay),
          ))
        .watchSingle()
        .map((row) => row.read(countExpr) ?? 0);
  }

  // =========================================================================
  // Mutations
  // =========================================================================

  /// Mark a kitchen ticket as completed ('served') and set [completedAt].
  ///
  /// The active-tickets stream will automatically remove it from the KDS UI.
  Future<void> completeTicket(String kitchenTicketId) async {
    await (_db.update(_db.kitchenTickets)
          ..where((t) => t.id.equals(kitchenTicketId)))
        .write(
      KitchenTicketsCompanion(
        status: const Value('served'),
        completedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Recall a previously bumped ticket — restores it to 'preparing' so it
  /// reappears on the KDS display. Used by the long-press recall gesture.
  Future<void> recallTicket(String kitchenTicketId) async {
    await (_db.update(_db.kitchenTickets)
          ..where((t) => t.id.equals(kitchenTicketId)))
        .write(
      const KitchenTicketsCompanion(
        status: Value('preparing'),
        completedAt: Value(null),
      ),
    );
  }

  /// Create a kitchen ticket (and its items) from a submitted POS ticket.
  ///
  /// [ticket] is the order ticket that was just sent to the kitchen.
  /// [items] are the unsent order items to include on the ticket.
  /// [waiterName] is the display name of the logged-in waiter (snapshot).
  Future<void> createTicketFromOrder({
    required TicketEntity ticket,
    required List<OrderItemEntity> items,
    String? waiterName,
  }) async {
    if (items.isEmpty) return;

    final now = DateTime.now();
    final kitchenTicketId = IdGenerator.generateId();

    // Resolve table display name if a tableId is present.
    String? tableName;
    if (ticket.tableId != null) {
      final tableRow = await (_db.select(_db.restaurantTables)
            ..where((t) => t.id.equals(ticket.tableId!)))
          .getSingleOrNull();
      tableName = tableRow?.name;
    }

    await _db.transaction(() async {
      await _db.into(_db.kitchenTickets).insert(
            KitchenTicketsCompanion(
              id: Value(kitchenTicketId),
              tenantId: Value(ticket.tenantId),
              ticketId: Value(ticket.id),
              kitchenTableName: Value(tableName),
              waiterName: Value(waiterName),
              orderNumber: Value(int.tryParse(ticket.orderNumber) ?? 0),
              printerGroup: const Value('kitchen'),
              status: const Value('pending'),
              sentAt: Value(now),
              createdAt: Value(now),
              isDeleted: const Value(false),
              syncStatus: const Value(0),
            ),
          );

      for (final item in items) {
        final modText = item.modifiers.isEmpty
            ? null
            : item.modifiers.map((m) => m.modifierName).join(', ');

        await _db.into(_db.kitchenTicketItems).insert(
              KitchenTicketItemsCompanion(
                id: Value(IdGenerator.generateId()),
                kitchenTicketId: Value(kitchenTicketId),
                orderItemId: Value(item.id),
                productName: Value(item.productName),
                quantity: Value(item.quantity),
                modifiersText: Value(modText),
                notes: Value(item.notes),
                status: const Value('pending'),
                createdAt: Value(now),
              ),
            );
      }
    });
  }

  // =========================================================================
  // Helpers
  // =========================================================================

  KitchenTicketEntity _toEntity(
    KitchenTicket row,
    List<KitchenTicketItem> itemRows,
  ) {
    final items = itemRows.map((i) {
      return KitchenTicketItemEntity(
        id: i.id,
        kitchenTicketId: i.kitchenTicketId,
        orderItemId: i.orderItemId,
        productName: i.productName,
        quantity: i.quantity,
        modifiersText: i.modifiersText,
        notes: i.notes,
        status: _parseItemStatus(i.status),
      );
    }).toList();

    return KitchenTicketEntity(
      id: row.id,
      tenantId: row.tenantId,
      ticketId: row.ticketId,
      tableName: row.kitchenTableName,
      waiterName: row.waiterName,
      orderNumber: row.orderNumber.toString().padLeft(4, '0'),
      printerGroup: row.printerGroup,
      status: _parseTicketStatus(row.status),
      items: items,
      sentAt: row.sentAt,
      startedAt: row.startedAt,
      completedAt: row.completedAt,
    );
  }

  static KitchenTicketStatus _parseTicketStatus(String value) {
    return switch (value) {
      'pending' => KitchenTicketStatus.pending,
      'acknowledged' => KitchenTicketStatus.acknowledged,
      'preparing' => KitchenTicketStatus.preparing,
      'ready' => KitchenTicketStatus.ready,
      'served' => KitchenTicketStatus.served,
      'void' => KitchenTicketStatus.voidStatus,
      _ => KitchenTicketStatus.pending,
    };
  }

  static KitchenTicketStatus _parseItemStatus(String value) =>
      _parseTicketStatus(value);

  static DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}
