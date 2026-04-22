/// Widget tests for the POS v2 shell footer.
///
/// Covers the Sipariş Ver / Zur Kasse split — the two-button layout that
/// only appears when the current ticket is bound to a dining table
/// (`ticket.tableId != null`). The aim is to guarantee three invariants
/// that tripped the pilot waiter:
///
///   1. Table mode → primary is "Sipariş Ver", secondary is "Zur Kasse";
///      the Schliessen / Neuer Bon / Senden triad is hidden.
///   2. Takeaway mode → the original triad comes back and neither of the
///      table-only buttons is rendered.
///   3. Tapping "Sipariş Ver" on a table ticket never shows the
///      "nicht bezahlt" warning dialog — parked bons are expected to sit
///      unpaid and the dialog was bogus noise.
///
/// We only need a minimal GoRouter so [_Footer]'s `context.go` survives;
/// the real router pulls in the whole shell which is not the unit under
/// test here.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/services/audit_service.dart';
import 'package:gastrocore_pos/features/audit_log/presentation/providers/audit_log_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/shells/pos_v2_shell.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Drop-in [CurrentTicketNotifier] for the footer tests.
///
/// The real notifier pulls in the whole DI stack (orderRepository, kitchen
/// repository, gang repository, audit service, ...); the footer only cares
/// about the state value and three method calls, so we stub those and
/// count invocations.
class _FakeTicketNotifier extends CurrentTicketNotifier {
  _FakeTicketNotifier(super.ref, TicketEntity? initial) {
    state = initial;
  }

  int sendToKitchenCalls = 0;
  int saveCalls = 0;
  int newTicketCalls = 0;

  @override
  Future<void> sendToKitchen() async {
    sendToKitchenCalls++;
    if (state != null) {
      state = state!.copyWith(status: TicketStatus.sent);
    }
  }

  @override
  Future<TicketEntity?> saveCurrentTicket() async {
    saveCalls++;
    return state;
  }

  @override
  Future<void> createNewTicket({
    OrderType orderType = OrderType.dineIn,
    String? tableId,
    String? waiterId,
    String? customerName,
    int guestCount = 1,
    required String deviceId,
  }) async {
    newTicketCalls++;
  }
}

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

TicketEntity _ticket({String? tableId}) {
  final now = DateTime(2026, 4, 22, 12, 0);
  // The footer gates every action on `hasItems`; an empty items list turns
  // Sipariş Ver / Zur Kasse into disabled no-ops whose taps never fire.
  // Seed one line so the tap handlers actually run.
  const item = OrderItemEntity(
    id: 'item-1',
    tenantId: 'tenant-test',
    ticketId: 'ticket-test',
    productId: 'prod-1',
    productName: 'Espresso',
    quantity: 1,
    unitPrice: 500,
    subtotal: 500,
  );
  return TicketEntity(
    id: 'ticket-test',
    tenantId: 'tenant-test',
    orderNumber: 'ORD-0001',
    orderType: OrderType.dineIn,
    tableId: tableId,
    status: TicketStatus.open,
    items: const [item],
    subtotal: 500,
    total: 500,
    openedAt: now,
    deviceId: 'DEV-POS-01',
  );
}

Future<_FakeTicketNotifier> _pumpFooter(
  WidgetTester tester, {
  required TicketEntity? ticket,
  required AppDatabase db,
}) async {
  late _FakeTicketNotifier notifier;
  final audit = AuditService(
    db: db,
    tenantId: 'tenant-test',
    deviceId: 'DEV-POS-01',
  );

  final router = GoRouter(
    initialLocation: '/sell',
    routes: [
      GoRoute(
        path: '/sell',
        builder: (_, __) => Scaffold(body: buildPosV2FooterForTest()),
      ),
      GoRoute(
        path: '/tables',
        builder: (_, __) => const Scaffold(body: Text('FLOOR-PLAN-SCREEN')),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('HOME-SCREEN')),
      ),
      GoRoute(
        path: '/payment/:ticketId',
        builder: (_, s) => Scaffold(
          body: Text('PAY-${s.pathParameters['ticketId']}'),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentTicketProvider.overrideWith((ref) {
          notifier = _FakeTicketNotifier(ref, ticket);
          return notifier;
        }),
        auditServiceProvider.overrideWithValue(audit),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('POS v2 Footer — table mode', () {
    testWidgets('renders Sipariş Ver + Zur Kasse, hides the triad',
        (tester) async {
      await _pumpFooter(
        tester,
        ticket: _ticket(tableId: 'table-M2'),
        db: db,
      );

      expect(find.text('Sipariş Ver'), findsOneWidget);
      expect(find.text('Zur Kasse'), findsOneWidget);
      expect(find.text('Schliessen'), findsNothing);
      expect(find.text('Neuer Bon'), findsNothing);
      expect(find.text('Senden'), findsNothing);
    });

    testWidgets('tap on Sipariş Ver persists and navigates back',
        (tester) async {
      final notifier = await _pumpFooter(
        tester,
        ticket: _ticket(tableId: 'table-M2'),
        db: db,
      );

      await tester.tap(find.text('Sipariş Ver'));
      // A single-frame pump is enough to drive the state change + nav; a
      // full pumpAndSettle would stall on the 2s snackbar timer that the
      // footer fires for operator feedback.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(notifier.sendToKitchenCalls, 1,
          reason: 'sendToKitchen must be invoked on Sipariş Ver');
      expect(find.text('FLOOR-PLAN-SCREEN'), findsOneWidget,
          reason: 'after dispatch we return to the floor plan');
    });

    testWidgets('tap on Sipariş Ver does NOT surface the unpaid dialog',
        (tester) async {
      await _pumpFooter(
        tester,
        ticket: _ticket(tableId: 'table-M2'),
        db: db,
      );

      await tester.tap(find.text('Sipariş Ver'));
      await tester.pumpAndSettle();

      // The legacy "aktueller Bon hat noch nicht bezahlt" warning must
      // never appear for a parked table order — the bon is supposed to
      // sit unpaid until the guest asks for the check.
      expect(find.textContaining('nicht bezahlt'), findsNothing);
      expect(find.textContaining('Bon schliessen?'), findsNothing);
    });

    testWidgets('tap on Zur Kasse persists and routes to payment',
        (tester) async {
      final notifier = await _pumpFooter(
        tester,
        ticket: _ticket(tableId: 'table-M2'),
        db: db,
      );

      await tester.tap(find.text('Zur Kasse'));
      await tester.pumpAndSettle();

      expect(notifier.saveCalls, 1);
      expect(find.text('PAY-ticket-test'), findsOneWidget);
    });
  });

  group('POS v2 Footer — takeaway mode', () {
    testWidgets('renders Schliessen + Neuer Bon + Senden, hides table buttons',
        (tester) async {
      await _pumpFooter(
        tester,
        ticket: _ticket(tableId: null),
        db: db,
      );

      expect(find.text('Schliessen'), findsOneWidget);
      expect(find.text('Neuer Bon'), findsOneWidget);
      expect(find.text('Senden'), findsOneWidget);
      expect(find.text('Sipariş Ver'), findsNothing);
      expect(find.text('Zur Kasse'), findsNothing);
    });
  });
}
