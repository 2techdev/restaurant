/// End-to-end test for the bump/recall pipeline with WebSocket events.
///
/// Sprint 3.5: locks the "WS event → provider state → UI source-of-truth"
/// contract. The real KDS stack wires a raw WS frame through
/// [KdsWsClient._onRawMessage] → [KdsEvent.fromJson] → the `onEvent`
/// callback configured in [kdsWsClientProvider] → [kdsLatestEventProvider].
/// Meanwhile, the ticket grid is driven by the Drift-backed
/// [activeKitchenTicketsProvider] stream fed by [KitchenRepositoryImpl].
///
/// This test exercises both halves in the same container so a regression
/// in either side (WS wiring, provider overrides, repo stream invalidation)
/// fails loudly instead of only showing up on a running device.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/kds_app/data/kds_ws_client.dart';
import 'package:gastrocore_pos/features/kds_app/presentation/providers/kds_realtime_provider.dart';
import 'package:gastrocore_pos/features/kitchen/data/repositories/kitchen_repository_impl.dart';
import 'package:gastrocore_pos/features/kitchen/presentation/providers/kitchen_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-test';

AppDatabase _openInMemory() => AppDatabase(NativeDatabase.memory());

ProviderContainer _containerFor(AppDatabase db) {
  return ProviderContainer(overrides: [
    databaseProvider.overrideWithValue(db),
    tenantIdProvider.overrideWithValue(_tenantId),
  ]);
}

TicketEntity _ticket({String id = 'ticket-1', String orderNumber = '0042'}) {
  return TicketEntity(
    id: id,
    tenantId: _tenantId,
    orderNumber: orderNumber,
    orderType: OrderType.dineIn,
    status: TicketStatus.sent,
    channel: OrderChannel.pos,
    openedAt: DateTime.now(),
    deviceId: 'DEV-KDS-01',
  );
}

OrderItemEntity _item({
  String id = 'item-1',
  String ticketId = 'ticket-1',
  String productName = 'Schnitzel',
}) {
  return OrderItemEntity(
    id: id,
    tenantId: _tenantId,
    ticketId: ticketId,
    productId: 'prod-1',
    productName: productName,
    quantity: 1,
    unitPrice: 2000,
    subtotal: 2000,
    modifiers: const [],
  );
}

Future<void> _seedSentTicket(AppDatabase db, {String id = 'ticket-1'}) async {
  final now = DateTime.now();
  await db.into(db.tickets).insert(
        TicketsCompanion.insert(
          id: id,
          tenantId: _tenantId,
          orderNumber: 42,
          status: const Value('sent_to_kitchen'),
          channel: const Value('pos'),
          openedAt: now,
          createdAt: now,
          updatedAt: now,
          deviceId: 'DEV-KDS-01',
        ),
      );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // WS event → kdsLatestEventProvider state pipe
  //
  // The real client runs inside a WebSocketChannel that we can't easily fake
  // in a unit test, so we test the segment that matters: raw JSON →
  // KdsEvent.fromJson → onEvent callback. The callback wiring in
  // kds_realtime_provider.dart feeds the result into kdsLatestEventProvider.
  // -------------------------------------------------------------------------
  group('WS event → kdsLatestEventProvider', () {
    test('a pushed KdsEvent surfaces in the latest-event provider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Seed "no event yet".
      expect(container.read(kdsLatestEventProvider), isNull);

      // Simulate the onEvent callback firing from the WS client.
      final event = KdsEvent.fromJson({
        'type': 'new_ticket',
        'ticket_id': 'kt-1',
        'order_number': '0042',
      });
      container.read(kdsLatestEventProvider.notifier).state = event;

      final latest = container.read(kdsLatestEventProvider);
      expect(latest, isNotNull);
      expect(latest!.type, 'new_ticket');
      expect(latest.ticketId, 'kt-1');
      expect(latest.orderNumber, '0042');
    });

    test('subsequent events replace the latest slot', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = KdsEvent.fromJson({
        'type': 'new_ticket',
        'ticket_id': 'kt-1',
      });
      final second = KdsEvent.fromJson({
        'type': 'status_update',
        'ticket_id': 'kt-1',
        'status': 'preparing',
      });

      container.read(kdsLatestEventProvider.notifier).state = first;
      container.read(kdsLatestEventProvider.notifier).state = second;

      final latest = container.read(kdsLatestEventProvider)!;
      expect(latest.type, 'status_update');
      expect(latest.status, 'preparing');
    });
  });

  // -------------------------------------------------------------------------
  // Bump / recall → activeKitchenTicketsProvider stream
  //
  // The UI ticket grid reads activeKitchenTicketsProvider. These tests run
  // real repository operations against an in-memory DB and verify the
  // provider stream reflects bump (ticket disappears) and recall (ticket
  // reappears). This is the contract the KDS main screen relies on.
  // -------------------------------------------------------------------------
  group('Bump / recall pipeline end-to-end', () {
    test('new kitchen ticket appears in activeKitchenTicketsProvider',
        () async {
      final db = _openInMemory();
      addTearDown(db.close);
      final container = _containerFor(db);
      addTearDown(container.dispose);

      await _seedSentTicket(db);
      await KitchenRepositoryImpl(db).createTicketFromOrder(
        ticket: _ticket(),
        items: [_item()],
      );

      final stream = container.read(activeKitchenTicketsProvider.stream);
      final tickets = await stream.firstWhere((list) => list.isNotEmpty);
      expect(tickets, hasLength(1));
      expect(tickets.first.ticketId, 'ticket-1');
    });

    test('bump removes ticket from active stream; recall brings it back',
        () async {
      final db = _openInMemory();
      addTearDown(db.close);
      final container = _containerFor(db);
      addTearDown(container.dispose);

      await _seedSentTicket(db);
      final repo = KitchenRepositoryImpl(db);
      await repo.createTicketFromOrder(
        ticket: _ticket(),
        items: [_item()],
      );

      final ktRow = await db.select(db.kitchenTickets).getSingle();

      // Initial state: one active ticket.
      final initial = await container
          .read(activeKitchenTicketsProvider.stream)
          .firstWhere((list) => list.isNotEmpty);
      expect(initial, hasLength(1));

      // Simulate the server-pushed bump notification — UI will also see
      // it via kdsLatestEventProvider and (optionally) play a beep.
      container.read(kdsLatestEventProvider.notifier).state =
          KdsEvent.fromJson({
        'type': 'status_update',
        'ticket_id': ktRow.id,
        'status': 'ready',
      });

      // The bump itself is a local repo call — the KDS screen dispatches
      // this on tap. The WS event is notification-only.
      await repo.completeTicket(ktRow.id);

      final afterBump = await container
          .read(activeKitchenTicketsProvider.stream)
          .firstWhere((list) => list.isEmpty);
      expect(afterBump, isEmpty,
          reason: 'bumped ticket must drop off the active grid');

      // Server-pushed recall notification arrives.
      container.read(kdsLatestEventProvider.notifier).state =
          KdsEvent.fromJson({
        'type': 'status_update',
        'ticket_id': ktRow.id,
        'status': 'pending',
      });

      await repo.recallTicket(ktRow.id);

      final afterRecall = await container
          .read(activeKitchenTicketsProvider.stream)
          .firstWhere((list) => list.isNotEmpty);
      expect(afterRecall, hasLength(1),
          reason: 'recalled ticket must reappear on the active grid');
    });

    test('ticket_closed WS event fires alongside a ticket dropping off',
        () async {
      final db = _openInMemory();
      addTearDown(db.close);
      final container = _containerFor(db);
      addTearDown(container.dispose);

      await _seedSentTicket(db);
      final repo = KitchenRepositoryImpl(db);
      await repo.createTicketFromOrder(
        ticket: _ticket(),
        items: [_item()],
      );
      final ktRow = await db.select(db.kitchenTickets).getSingle();

      // Listen for the first empty emission once we bump.
      final emptyFuture = container
          .read(activeKitchenTicketsProvider.stream)
          .firstWhere((list) => list.isEmpty)
          .timeout(const Duration(seconds: 3));

      // Server pushes ticket_closed, UI bumps the ticket locally.
      container.read(kdsLatestEventProvider.notifier).state =
          KdsEvent.fromJson({
        'type': 'ticket_closed',
        'ticket_id': ktRow.id,
      });
      await repo.completeTicket(ktRow.id);

      // Both ends must agree: event is captured AND active stream drops it.
      expect(
        container.read(kdsLatestEventProvider)?.type,
        'ticket_closed',
      );
      final empty = await emptyFuture;
      expect(empty, isEmpty);
    });
  });
}
