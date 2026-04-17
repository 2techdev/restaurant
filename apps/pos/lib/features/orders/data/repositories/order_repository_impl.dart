/// Drift-backed implementation of the order (ticket) repository.
///
/// This is the most critical repository in the POS system. It manages the
/// full lifecycle of tickets: creation, item management, status transitions,
/// and total calculations. Multi-table mutations (ticket + items + modifiers)
/// are wrapped in database transactions.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';

class OrderRepositoryImpl {
  final AppDatabase _db;

  OrderRepositoryImpl(this._db);

  // =========================================================================
  // Ticket CRUD
  // =========================================================================

  /// Create a new ticket together with all its items and item-modifiers
  /// inside a single transaction.
  ///
  /// Returns the persisted [TicketEntity] with items populated.
  Future<TicketEntity> createTicket(TicketEntity ticket) async {
    await _db.transaction(() async {
      // 1. Insert the ticket row.
      await _db.into(_db.tickets).insert(_ticketToCompanion(ticket));

      // 2. Insert each order item and its modifiers.
      for (final item in ticket.items) {
        await _db.into(_db.orderItems).insert(_orderItemToCompanion(item));

        for (final mod in item.modifiers) {
          await _db.into(_db.orderItemModifiers).insert(
                OrderItemModifiersCompanion(
                  id: Value(mod.id),
                  orderItemId: Value(mod.orderItemId),
                  modifierId: Value(mod.modifierId),
                  modifierName: Value(mod.modifierName),
                  priceDelta: Value(mod.priceDelta),
                  createdAt: Value(DateTime.now()),
                ),
              );
        }
      }
    });

    // Return the fully hydrated entity.
    return (await getTicketById(ticket.id))!;
  }

  /// Fetch a ticket by [id] with all items and item-modifiers loaded.
  Future<TicketEntity?> getTicketById(String id) async {
    final query = _db.select(_db.tickets)
      ..where((t) => t.id.equals(id) & t.isDeleted.equals(false));
    final row = await query.getSingleOrNull();
    if (row == null) return null;

    final items = await _loadItemsForTicket(id);
    return _ticketToEntity(row, items);
  }

  /// Return all open tickets (not completed / cancelled / voided) for
  /// [tenantId], ordered by most recent first.
  Future<List<TicketEntity>> getOpenTickets(String tenantId) async {
    final closedStatuses = ['completed', 'cancelled', 'voided', 'fully_paid', 'closed'];
    final query = _db.select(_db.tickets)
      ..where(
        (t) =>
            t.tenantId.equals(tenantId) &
            t.isDeleted.equals(false) &
            t.status.isNotIn(closedStatuses),
      )
      ..orderBy([
        (t) => OrderingTerm.desc(t.openedAt),
        (t) => OrderingTerm(expression: t.rowId, mode: OrderingMode.desc),
      ]);
    final rows = await query.get();

    final results = <TicketEntity>[];
    for (final row in rows) {
      final items = await _loadItemsForTicket(row.id);
      results.add(_ticketToEntity(row, items));
    }
    return results;
  }

  /// Return all tickets for [tenantId], regardless of status.
  Future<List<TicketEntity>> getAllTickets(String tenantId) async {
    final query = _db.select(_db.tickets)
      ..where(
        (t) => t.tenantId.equals(tenantId) & t.isDeleted.equals(false),
      )
      ..orderBy([
        (t) => OrderingTerm.desc(t.openedAt),
        (t) => OrderingTerm(expression: t.rowId, mode: OrderingMode.desc),
      ]);
    final rows = await query.get();

    final results = <TicketEntity>[];
    for (final row in rows) {
      final items = await _loadItemsForTicket(row.id);
      results.add(_ticketToEntity(row, items));
    }
    return results;
  }

  /// Return tickets assigned to [tableId] that are still open.
  Future<List<TicketEntity>> getTicketsByTable(String tableId) async {
    final closedStatuses = ['completed', 'cancelled', 'voided', 'fully_paid', 'closed'];
    final query = _db.select(_db.tickets)
      ..where(
        (t) =>
            t.tableId.equals(tableId) &
            t.isDeleted.equals(false) &
            t.status.isNotIn(closedStatuses),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.openedAt)]);
    final rows = await query.get();

    final results = <TicketEntity>[];
    for (final row in rows) {
      final items = await _loadItemsForTicket(row.id);
      results.add(_ticketToEntity(row, items));
    }
    return results;
  }

  /// Return all tickets for a given [shiftId] and [tenantId].
  /// Used for shift close-out reporting.
  Future<List<TicketEntity>> getTicketsForShift(
    String shiftId,
    String tenantId,
  ) async {
    // Tickets created during a shift are determined by the openedAt timestamp
    // falling within the shift window. We look up the shift first.
    final shiftQuery = _db.select(_db.shifts)
      ..where((s) => s.id.equals(shiftId));
    final shift = await shiftQuery.getSingleOrNull();
    if (shift == null) return const [];

    var query = _db.select(_db.tickets)
      ..where(
        (t) =>
            t.tenantId.equals(tenantId) &
            t.isDeleted.equals(false) &
            t.openedAt.isBiggerOrEqualValue(shift.openedAt),
      );

    // If the shift is closed, scope to tickets opened before close time.
    if (shift.closedAt != null) {
      query = _db.select(_db.tickets)
        ..where(
          (t) =>
              t.tenantId.equals(tenantId) &
              t.isDeleted.equals(false) &
              t.openedAt.isBiggerOrEqualValue(shift.openedAt) &
              t.openedAt.isSmallerOrEqualValue(shift.closedAt!),
        );
    }

    query.orderBy([(t) => OrderingTerm.asc(t.openedAt)]);
    final rows = await query.get();

    final results = <TicketEntity>[];
    for (final row in rows) {
      final items = await _loadItemsForTicket(row.id);
      results.add(_ticketToEntity(row, items));
    }
    return results;
  }

  // =========================================================================
  // Ticket status
  // =========================================================================

  /// Update the lifecycle status of a ticket.
  Future<void> updateTicketStatus(String id, TicketStatus newStatus) async {
    final companion = TicketsCompanion(
      status: Value(_ticketStatusToString(newStatus)),
      updatedAt: Value(DateTime.now()),
      closedAt: (newStatus == TicketStatus.completed ||
              newStatus == TicketStatus.cancelled ||
              newStatus == TicketStatus.voided)
          ? Value(DateTime.now())
          : const Value.absent(),
    );
    await (_db.update(_db.tickets)..where((t) => t.id.equals(id)))
        .write(companion);
  }

  /// Reassign a ticket to a different table.
  ///
  /// Used by the waiter table-transfer flow. The caller is responsible for
  /// updating old/new table statuses — this method only rewrites the ticket
  /// row itself.
  Future<void> updateTicketTable(String id, String newTableId) async {
    await (_db.update(_db.tickets)..where((t) => t.id.equals(id))).write(
      TicketsCompanion(
        tableId: Value(newTableId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // =========================================================================
  // Order items
  // =========================================================================

  /// Add a single item (with modifiers) to an existing ticket and
  /// recalculate totals.
  Future<void> addItemToTicket(
    String ticketId,
    OrderItemEntity item,
  ) async {
    await _db.transaction(() async {
      await _db.into(_db.orderItems).insert(_orderItemToCompanion(item));

      for (final mod in item.modifiers) {
        await _db.into(_db.orderItemModifiers).insert(
              OrderItemModifiersCompanion(
                id: Value(mod.id),
                orderItemId: Value(mod.orderItemId),
                modifierId: Value(mod.modifierId),
                modifierName: Value(mod.modifierName),
                priceDelta: Value(mod.priceDelta),
                createdAt: Value(DateTime.now()),
              ),
            );
      }

      await calculateTicketTotals(ticketId);
    });
  }

  /// Soft-delete an order item and recalculate ticket totals.
  Future<void> removeItemFromTicket(String orderItemId) async {
    // Look up the ticketId before deletion.
    final itemQuery = _db.select(_db.orderItems)
      ..where((i) => i.id.equals(orderItemId));
    final item = await itemQuery.getSingleOrNull();
    if (item == null) return;

    await _db.transaction(() async {
      await (_db.update(_db.orderItems)
            ..where((i) => i.id.equals(orderItemId)))
          .write(
        OrderItemsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await calculateTicketTotals(item.ticketId);
    });
  }

  /// Update the quantity of an order item and recalculate ticket totals.
  Future<void> updateItemQuantity(String orderItemId, int newQty) async {
    final itemQuery = _db.select(_db.orderItems)
      ..where((i) => i.id.equals(orderItemId));
    final item = await itemQuery.getSingleOrNull();
    if (item == null) return;

    // Load modifiers to recalculate subtotal.
    final modsQuery = _db.select(_db.orderItemModifiers)
      ..where((m) => m.orderItemId.equals(orderItemId));
    final mods = await modsQuery.get();
    final modifierTotal = mods.fold<int>(0, (s, m) => s + m.priceDelta);
    final newSubtotal = ((item.unitPrice + modifierTotal) * newQty);

    await _db.transaction(() async {
      await (_db.update(_db.orderItems)
            ..where((i) => i.id.equals(orderItemId)))
          .write(
        OrderItemsCompanion(
          quantity: Value(newQty.toDouble()),
          subtotal: Value(newSubtotal),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await calculateTicketTotals(item.ticketId);
    });
  }

  /// Update the preparation status of an order item.
  Future<void> updateItemStatus(
    String orderItemId,
    OrderItemStatus newStatus,
  ) async {
    await (_db.update(_db.orderItems)
          ..where((i) => i.id.equals(orderItemId)))
        .write(
      OrderItemsCompanion(
        status: Value(_orderItemStatusToString(newStatus)),
        sentToKitchen: newStatus == OrderItemStatus.sent ||
                newStatus == OrderItemStatus.preparing ||
                newStatus == OrderItemStatus.ready ||
                newStatus == OrderItemStatus.served
            ? const Value(true)
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // =========================================================================
  // Order number generation
  // =========================================================================

  /// Return the next sequential order number for today within [tenantId].
  ///
  /// Counts existing tickets opened today and increments by one.
  Future<int> getNextOrderNumber(String tenantId) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final countExpr = _db.tickets.id.count();
    final query = _db.selectOnly(_db.tickets)
      ..addColumns([countExpr])
      ..where(
        _db.tickets.tenantId.equals(tenantId) &
            _db.tickets.isDeleted.equals(false) &
            _db.tickets.openedAt.isBiggerOrEqualValue(startOfDay) &
            _db.tickets.openedAt.isSmallerThanValue(endOfDay),
      );
    final result = await query.getSingle();
    final count = result.read(countExpr) ?? 0;
    return count + 1;
  }

  // =========================================================================
  // Discount
  // =========================================================================

  /// Persist discount settings on a ticket, then recalculate totals.
  Future<void> updateTicketDiscount(
    String ticketId, {
    required DiscountType discountType,
    required int discountValue,
  }) async {
    await (_db.update(_db.tickets)..where((t) => t.id.equals(ticketId))).write(
      TicketsCompanion(
        discountType: Value(_discountTypeToString(discountType)),
        discountValue: Value(discountValue.toDouble()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await calculateTicketTotals(ticketId);
  }

  /// Remove discount from a ticket, then recalculate totals.
  Future<void> removeTicketDiscount(String ticketId) async {
    await (_db.update(_db.tickets)..where((t) => t.id.equals(ticketId))).write(
      TicketsCompanion(
        discountType: const Value(null),
        discountValue: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await calculateTicketTotals(ticketId);
  }

  // =========================================================================
  // Total calculation
  // =========================================================================

  /// Recalculate and persist the subtotal, tax, and total for a ticket
  /// based on its non-deleted order items.
  Future<void> calculateTicketTotals(String ticketId) async {
    final itemsQuery = _db.select(_db.orderItems)
      ..where(
        (i) => i.ticketId.equals(ticketId) & i.isDeleted.equals(false),
      );
    final items = await itemsQuery.get();

    final subtotal = items.fold<int>(0, (s, i) => s + i.subtotal);
    final taxAmount = items.fold<int>(0, (s, i) => s + i.taxAmount);

    // Read the current discount settings from the ticket.
    final ticketQuery = _db.select(_db.tickets)
      ..where((t) => t.id.equals(ticketId));
    final ticket = await ticketQuery.getSingle();

    int discountAmount = 0;
    if (ticket.discountType == 'fixed' && ticket.discountValue != null) {
      discountAmount = ticket.discountValue!.round();
    } else if (ticket.discountType == 'percentage' &&
        ticket.discountValue != null) {
      discountAmount = (subtotal * ticket.discountValue! / 100).round();
    }

    final total = subtotal + taxAmount - discountAmount;

    await (_db.update(_db.tickets)..where((t) => t.id.equals(ticketId))).write(
      TicketsCompanion(
        subtotal: Value(subtotal),
        taxAmount: Value(taxAmount),
        discountAmount: Value(discountAmount),
        total: Value(total < 0 ? 0 : total),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // =========================================================================
  // Private helpers
  // =========================================================================

  /// Load all non-deleted items (with their modifiers) for a given ticket.
  Future<List<OrderItemEntity>> _loadItemsForTicket(String ticketId) async {
    final query = _db.select(_db.orderItems)
      ..where(
        (i) => i.ticketId.equals(ticketId) & i.isDeleted.equals(false),
      )
      ..orderBy([(i) => OrderingTerm.asc(i.createdAt)]);
    final rows = await query.get();

    if (rows.isEmpty) return const [];

    // Batch-load all modifiers for these items.
    final itemIds = rows.map((r) => r.id).toList();
    final modQuery = _db.select(_db.orderItemModifiers)
      ..where((m) => m.orderItemId.isIn(itemIds));
    final modRows = await modQuery.get();

    final modsByItem = <String, List<OrderItemModifierEntity>>{};
    for (final m in modRows) {
      modsByItem.putIfAbsent(m.orderItemId, () => []).add(
            OrderItemModifierEntity(
              id: m.id,
              orderItemId: m.orderItemId,
              modifierId: m.modifierId,
              modifierName: m.modifierName,
              priceDelta: m.priceDelta,
            ),
          );
    }

    return rows.map((r) {
      return _orderItemToEntity(r, modsByItem[r.id] ?? const []);
    }).toList();
  }

  // =========================================================================
  // Mappers – Ticket
  // =========================================================================

  TicketEntity _ticketToEntity(Ticket row, List<OrderItemEntity> items) {
    return TicketEntity(
      id: row.id,
      tenantId: row.tenantId,
      orderNumber: row.orderNumber.toString().padLeft(4, '0'),
      orderType: _parseOrderType(row.orderType),
      tableId: row.tableId,
      waiterId: row.waiterId,
      customerName: row.customerName,
      guestCount: row.guestCount,
      status: _parseTicketStatus(row.status),
      channel: _parseOrderChannel(row.channel),
      items: items,
      subtotal: row.subtotal,
      taxAmount: row.taxAmount,
      discountAmount: row.discountAmount,
      discountType: _parseDiscountType(row.discountType),
      discountValue: row.discountValue?.round() ?? 0,
      total: row.total,
      notes: row.notes,
      openedAt: row.openedAt,
      closedAt: row.closedAt,
      deviceId: row.deviceId,
    );
  }

  TicketsCompanion _ticketToCompanion(TicketEntity entity) {
    return TicketsCompanion(
      id: Value(entity.id),
      tenantId: Value(entity.tenantId),
      orderNumber: Value(int.tryParse(entity.orderNumber) ?? 0),
      orderType: Value(_orderTypeToString(entity.orderType)),
      tableId: Value(entity.tableId),
      waiterId: Value(entity.waiterId),
      customerName: Value(entity.customerName),
      guestCount: Value(entity.guestCount),
      status: Value(_ticketStatusToString(entity.status)),
      channel: Value(_orderChannelToString(entity.channel)),
      subtotal: Value(entity.subtotal),
      taxAmount: Value(entity.taxAmount),
      discountAmount: Value(entity.discountAmount),
      discountType: Value(_discountTypeToString(entity.discountType)),
      discountValue: Value(entity.discountValue.toDouble()),
      total: Value(entity.total),
      notes: Value(entity.notes),
      openedAt: Value(entity.openedAt),
      closedAt: Value(entity.closedAt),
      deviceId: Value(entity.deviceId),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
      syncStatus: const Value(0),
    );
  }

  // =========================================================================
  // Mappers – Order item
  // =========================================================================

  OrderItemEntity _orderItemToEntity(
    OrderItem row,
    List<OrderItemModifierEntity> modifiers,
  ) {
    return OrderItemEntity(
      id: row.id,
      tenantId: row.tenantId,
      ticketId: row.ticketId,
      productId: row.productId,
      productName: row.productName,
      quantity: row.quantity,
      unitPrice: row.unitPrice,
      subtotal: row.subtotal,
      taxAmount: row.taxAmount,
      discountAmount: row.discountAmount,
      status: _parseOrderItemStatus(row.status),
      sentToKitchen: row.sentToKitchen,
      notes: row.notes,
      course: row.course,
      gangId: row.gangId,
      modifiers: modifiers,
    );
  }

  OrderItemsCompanion _orderItemToCompanion(OrderItemEntity entity) {
    return OrderItemsCompanion(
      id: Value(entity.id),
      tenantId: Value(entity.tenantId),
      ticketId: Value(entity.ticketId),
      productId: Value(entity.productId),
      productName: Value(entity.productName),
      quantity: Value(entity.quantity),
      unitPrice: Value(entity.unitPrice),
      subtotal: Value(entity.subtotal),
      taxAmount: Value(entity.taxAmount),
      discountAmount: Value(entity.discountAmount),
      status: Value(_orderItemStatusToString(entity.status)),
      sentToKitchen: Value(entity.sentToKitchen),
      notes: Value(entity.notes),
      course: Value(entity.course),
      gangId: Value(entity.gangId),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
      syncStatus: const Value(0),
    );
  }

  // =========================================================================
  // Enum serialisation helpers
  // =========================================================================

  static OrderType _parseOrderType(String value) {
    return switch (value) {
      'dine_in' => OrderType.dineIn,
      'takeaway' => OrderType.takeaway,
      'delivery' => OrderType.delivery,
      'online' => OrderType.online,
      _ => OrderType.dineIn,
    };
  }

  static String _orderTypeToString(OrderType type) {
    return switch (type) {
      OrderType.dineIn => 'dine_in',
      OrderType.takeaway => 'takeaway',
      OrderType.delivery => 'delivery',
      OrderType.online => 'online',
    };
  }

  static TicketStatus _parseTicketStatus(String value) {
    return switch (value) {
      'draft' => TicketStatus.draft,
      'open' => TicketStatus.open,
      'sent' => TicketStatus.sent,
      'in_progress' => TicketStatus.inProgress,
      'ready' => TicketStatus.ready,
      'served' => TicketStatus.served,
      'bill_requested' => TicketStatus.billRequested,
      'completed' || 'fully_paid' || 'closed' => TicketStatus.completed,
      'cancelled' => TicketStatus.cancelled,
      'voided' || 'void' => TicketStatus.voided,
      _ => TicketStatus.open,
    };
  }

  static String _ticketStatusToString(TicketStatus status) {
    return switch (status) {
      TicketStatus.draft => 'draft',
      TicketStatus.open => 'open',
      TicketStatus.sent => 'sent',
      TicketStatus.inProgress => 'in_progress',
      TicketStatus.ready => 'ready',
      TicketStatus.served => 'served',
      TicketStatus.billRequested => 'bill_requested',
      TicketStatus.completed => 'completed',
      TicketStatus.cancelled => 'cancelled',
      TicketStatus.voided => 'voided',
    };
  }

  static OrderChannel _parseOrderChannel(String value) {
    return switch (value) {
      'pos' => OrderChannel.pos,
      'waiter' => OrderChannel.waiter,
      'qr' => OrderChannel.qr,
      'kiosk' => OrderChannel.kiosk,
      'web' => OrderChannel.web,
      _ => OrderChannel.pos,
    };
  }

  static String _orderChannelToString(OrderChannel channel) {
    return switch (channel) {
      OrderChannel.pos => 'pos',
      OrderChannel.waiter => 'waiter',
      OrderChannel.qr => 'qr',
      OrderChannel.kiosk => 'kiosk',
      OrderChannel.web => 'web',
    };
  }

  static DiscountType _parseDiscountType(String? value) {
    return switch (value) {
      'fixed' => DiscountType.fixed,
      'percentage' || 'percent' => DiscountType.percentage,
      _ => DiscountType.none,
    };
  }

  static String? _discountTypeToString(DiscountType type) {
    return switch (type) {
      DiscountType.none => null,
      DiscountType.fixed => 'fixed',
      DiscountType.percentage => 'percentage',
    };
  }

  static OrderItemStatus _parseOrderItemStatus(String value) {
    return switch (value) {
      'ordered' => OrderItemStatus.ordered,
      'sent' => OrderItemStatus.sent,
      'preparing' => OrderItemStatus.preparing,
      'ready' => OrderItemStatus.ready,
      'served' => OrderItemStatus.served,
      'void' => OrderItemStatus.voidStatus,
      _ => OrderItemStatus.ordered,
    };
  }

  static String _orderItemStatusToString(OrderItemStatus status) {
    return switch (status) {
      OrderItemStatus.ordered => 'ordered',
      OrderItemStatus.sent => 'sent',
      OrderItemStatus.preparing => 'preparing',
      OrderItemStatus.ready => 'ready',
      OrderItemStatus.served => 'served',
      OrderItemStatus.voidStatus => 'void',
    };
  }
}
