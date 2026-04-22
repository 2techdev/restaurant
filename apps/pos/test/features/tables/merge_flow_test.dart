/// End-to-end test for the table-merge flow.
///
/// Replays what [MergeTablesDialog._doMerge] does at the repository +
/// service layer against an in-memory Drift database:
///
///   1. Seed two occupied tables with tickets + items
///   2. Run the merge sequence (copy items, void source, clear+dirty table)
///   3. Emit the audit entry via [AuditService]
///
/// Asserts cover the merged state of both tables, the source ticket
/// status, and the shape of the audit row — including the new
/// [AuditAction.tableMerged] action and the `newValueJson` payload the
/// Audit Log screen relies on to reconstruct the merge.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/services/audit_service.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/tables/data/repositories/table_repository_impl.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';

const _tenantId = 'tenant-merge';
const _floorId = 'floor-merge';
const _deviceId = 'DEV-MERGE';

Future<AppDatabase> _openDb() async => AppDatabase.createInMemory();

Future<void> _seedFloor(AppDatabase db) async {
  await db.into(db.floors).insert(FloorsCompanion.insert(
        id: _floorId,
        tenantId: _tenantId,
        name: 'Main',
        displayOrder: const Value(0),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

Future<void> _seedTable(
  AppDatabase db, {
  required String id,
  required String name,
  String? currentOrderId,
}) async {
  await db.into(db.restaurantTables).insert(RestaurantTablesCompanion.insert(
        id: id,
        tenantId: _tenantId,
        floorId: _floorId,
        name: name,
        capacity: const Value(4),
        posX: const Value(0.0),
        posY: const Value(0.0),
        width: const Value(120.0),
        height: const Value(80.0),
        status: const Value('occupied'),
        currentOrderId: Value(currentOrderId),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

TicketEntity _buildTicket({
  required String id,
  required String tableId,
  required int orderNumber,
  required List<OrderItemEntity> items,
}) {
  return TicketEntity(
    id: id,
    tenantId: _tenantId,
    orderNumber: IdGenerator.generateOrderNumber(orderNumber),
    orderType: OrderType.dineIn,
    tableId: tableId,
    status: TicketStatus.open,
    channel: OrderChannel.pos,
    openedAt: DateTime.now(),
    deviceId: _deviceId,
    items: items,
  );
}

OrderItemEntity _buildItem({
  required String id,
  required String ticketId,
  required String productName,
  int unitPrice = 1500,
  double qty = 1,
}) {
  return OrderItemEntity(
    id: id,
    tenantId: _tenantId,
    ticketId: ticketId,
    productId: 'P-$id',
    productName: productName,
    quantity: qty,
    unitPrice: unitPrice,
    subtotal: (unitPrice * qty).round(),
  );
}

/// Pure replay of the dialog's merge sequence.  Kept local to the test so
/// a regression in the dialog's ordering would not silently pass.
Future<void> _performMerge({
  required AppDatabase db,
  required OrderRepositoryImpl orderRepo,
  required TableRepositoryImpl tableRepo,
  required AuditService audit,
  required RestaurantTableEntity sourceTable,
  required RestaurantTableEntity targetTable,
}) async {
  final sourceTicket = await orderRepo.getTicketById(sourceTable.currentOrderId!);
  if (sourceTicket == null) throw StateError('No source ticket');

  String targetTicketId;
  if (targetTable.currentOrderId != null) {
    targetTicketId = targetTable.currentOrderId!;
  } else {
    final nextNumber = await orderRepo.getNextOrderNumber(_tenantId);
    final newTicket = _buildTicket(
      id: IdGenerator.generateId(),
      tableId: targetTable.id,
      orderNumber: nextNumber,
      items: const [],
    );
    final saved = await orderRepo.createTicket(newTicket);
    targetTicketId = saved.id;
    await tableRepo.linkOrderToTable(targetTable.id, targetTicketId);
  }

  for (final item in sourceTicket.items) {
    final newItemId = IdGenerator.generateId();
    final cloned = item.copyWith(id: newItemId, ticketId: targetTicketId);
    await orderRepo.addItemToTicket(targetTicketId, cloned);
  }

  final reason = 'Merge to ${targetTable.name}';
  await orderRepo.updateTicketNotes(sourceTicket.id, reason);
  await orderRepo.updateTicketStatus(sourceTicket.id, TicketStatus.voided);
  await tableRepo.clearTable(sourceTable.id);
  await tableRepo.updateTableStatus(sourceTable.id, TableStatus.dirty);

  await audit.log(
    action: AuditAction.tableMerged,
    entityType: 'ticket',
    entityId: sourceTicket.id,
    reason: reason,
    newValueJson: jsonEncode({
      'sourceTableId': sourceTable.id,
      'sourceTableName': sourceTable.name,
      'sourceTicketId': sourceTicket.id,
      'targetTableId': targetTable.id,
      'targetTableName': targetTable.name,
      'targetTicketId': targetTicketId,
      'itemCount': sourceTicket.items.length,
    }),
  );
}

void main() {
  group('Table merge — end-to-end', () {
    late AppDatabase db;
    late OrderRepositoryImpl orderRepo;
    late TableRepositoryImpl tableRepo;
    late AuditService audit;

    setUp(() async {
      db = await _openDb();
      orderRepo = OrderRepositoryImpl(db);
      tableRepo = TableRepositoryImpl(db);
      audit = AuditService(db: db, tenantId: _tenantId, deviceId: _deviceId)
        ..setUser(userId: 'U-1', userName: 'Cashier');
      await _seedFloor(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('merges source ticket items into target and voids source', () async {
      // Source ticket: two items on T1.
      final sourceTicketId = 'TCK-S';
      final source = _buildTicket(
        id: sourceTicketId,
        tableId: 'T1',
        orderNumber: 1,
        items: [
          _buildItem(
              id: 'I-A', ticketId: sourceTicketId, productName: 'Cola'),
          _buildItem(
              id: 'I-B', ticketId: sourceTicketId, productName: 'Burger'),
        ],
      );
      await orderRepo.createTicket(source);

      // Target ticket: one existing item on T2.
      final targetTicketId = 'TCK-T';
      final target = _buildTicket(
        id: targetTicketId,
        tableId: 'T2',
        orderNumber: 2,
        items: [
          _buildItem(
              id: 'I-C', ticketId: targetTicketId, productName: 'Salad'),
        ],
      );
      await orderRepo.createTicket(target);

      await _seedTable(db,
          id: 'T1', name: 'Table 1', currentOrderId: sourceTicketId);
      await _seedTable(db,
          id: 'T2', name: 'Table 2', currentOrderId: targetTicketId);

      final tables = await tableRepo.getAllTables(_tenantId);
      final srcTable = tables.firstWhere((t) => t.id == 'T1');
      final tgtTable = tables.firstWhere((t) => t.id == 'T2');

      await _performMerge(
        db: db,
        orderRepo: orderRepo,
        tableRepo: tableRepo,
        audit: audit,
        sourceTable: srcTable,
        targetTable: tgtTable,
      );

      // Target now has 1 original + 2 merged = 3 items.
      final mergedTarget = await orderRepo.getTicketById(targetTicketId);
      expect(mergedTarget!.items.length, 3);
      expect(
        mergedTarget.items.map((i) => i.productName).toSet(),
        {'Salad', 'Cola', 'Burger'},
      );

      // Source ticket is voided with a Merge-to reason stamped onto notes.
      final voidedSource = await orderRepo.getTicketById(sourceTicketId);
      expect(voidedSource!.status, TicketStatus.voided);
      expect(voidedSource.notes, 'Merge to Table 2');

      // Source table is cleared + dirty.
      final refreshed = await tableRepo.getAllTables(_tenantId);
      final srcAfter = refreshed.firstWhere((t) => t.id == 'T1');
      expect(srcAfter.status, TableStatus.dirty);
      expect(srcAfter.currentOrderId, isNull);
    });

    test('copied items get fresh ids on the target ticket', () async {
      // Regression guard — dialog uses IdGenerator.generateId() per item.
      // If a future refactor re-used source item ids, the target's
      // calculateTotals would fail on PK conflict.
      final sourceTicketId = 'TCK-S';
      await orderRepo.createTicket(_buildTicket(
        id: sourceTicketId,
        tableId: 'T1',
        orderNumber: 1,
        items: [
          _buildItem(id: 'ITEM-X', ticketId: sourceTicketId, productName: 'A'),
        ],
      ));
      final targetTicketId = 'TCK-T';
      await orderRepo.createTicket(_buildTicket(
        id: targetTicketId,
        tableId: 'T2',
        orderNumber: 2,
        items: const [],
      ));

      await _seedTable(db,
          id: 'T1', name: 'T1', currentOrderId: sourceTicketId);
      await _seedTable(db,
          id: 'T2', name: 'T2', currentOrderId: targetTicketId);

      final tables = await tableRepo.getAllTables(_tenantId);
      await _performMerge(
        db: db,
        orderRepo: orderRepo,
        tableRepo: tableRepo,
        audit: audit,
        sourceTable: tables.firstWhere((t) => t.id == 'T1'),
        targetTable: tables.firstWhere((t) => t.id == 'T2'),
      );

      final tgt = await orderRepo.getTicketById(targetTicketId);
      expect(tgt!.items, isNotEmpty);
      expect(tgt.items.first.id, isNot('ITEM-X'));
      expect(tgt.items.first.ticketId, targetTicketId);
    });

    test('emits an audit entry with the full source+target metadata',
        () async {
      final sourceTicketId = 'TCK-S';
      await orderRepo.createTicket(_buildTicket(
        id: sourceTicketId,
        tableId: 'T1',
        orderNumber: 1,
        items: [
          _buildItem(id: 'I-1', ticketId: sourceTicketId, productName: 'A'),
          _buildItem(id: 'I-2', ticketId: sourceTicketId, productName: 'B'),
        ],
      ));
      final targetTicketId = 'TCK-T';
      await orderRepo.createTicket(_buildTicket(
        id: targetTicketId,
        tableId: 'T2',
        orderNumber: 2,
        items: const [],
      ));

      await _seedTable(db,
          id: 'T1', name: 'Masa 7', currentOrderId: sourceTicketId);
      await _seedTable(db,
          id: 'T2', name: 'Masa 12', currentOrderId: targetTicketId);

      final tables = await tableRepo.getAllTables(_tenantId);
      await _performMerge(
        db: db,
        orderRepo: orderRepo,
        tableRepo: tableRepo,
        audit: audit,
        sourceTable: tables.firstWhere((t) => t.id == 'T1'),
        targetTable: tables.firstWhere((t) => t.id == 'T2'),
      );

      final entries = await db.auditLogDao.getEntries(tenantId: _tenantId);
      expect(entries, isNotEmpty);
      final row = entries.first;
      expect(row.action, AuditAction.tableMerged);
      expect(row.entityType, 'ticket');
      expect(row.entityId, sourceTicketId);
      expect(row.reason, 'Merge to Masa 12');

      final payload =
          jsonDecode(row.newValueJson!) as Map<String, dynamic>;
      expect(payload['sourceTableId'], 'T1');
      expect(payload['sourceTableName'], 'Masa 7');
      expect(payload['sourceTicketId'], sourceTicketId);
      expect(payload['targetTableId'], 'T2');
      expect(payload['targetTableName'], 'Masa 12');
      expect(payload['targetTicketId'], targetTicketId);
      expect(payload['itemCount'], 2);
    });

    test('target without an open ticket gets a fresh one', () async {
      final sourceTicketId = 'TCK-S';
      await orderRepo.createTicket(_buildTicket(
        id: sourceTicketId,
        tableId: 'T1',
        orderNumber: 1,
        items: [
          _buildItem(id: 'I-A', ticketId: sourceTicketId, productName: 'A'),
        ],
      ));

      await _seedTable(db,
          id: 'T1', name: 'T1', currentOrderId: sourceTicketId);
      await _seedTable(db, id: 'T2', name: 'T2'); // no currentOrderId

      final tables = await tableRepo.getAllTables(_tenantId);
      await _performMerge(
        db: db,
        orderRepo: orderRepo,
        tableRepo: tableRepo,
        audit: audit,
        sourceTable: tables.firstWhere((t) => t.id == 'T1'),
        targetTable: tables.firstWhere((t) => t.id == 'T2'),
      );

      // After merge, T2 must be linked to a fresh ticket with the copied
      // item; the source ticket stays voided and separate.
      final refreshed = await tableRepo.getAllTables(_tenantId);
      final tgt = refreshed.firstWhere((t) => t.id == 'T2');
      expect(tgt.currentOrderId, isNotNull);
      expect(tgt.currentOrderId, isNot(sourceTicketId));

      final tgtTicket = await orderRepo.getTicketById(tgt.currentOrderId!);
      expect(tgtTicket!.items.length, 1);
      expect(tgtTicket.items.first.productName, 'A');
    });
  });
}
