/// Widget tests for [SeatSelector] — the waiter's sticky cover-picker chip row.
///
/// Verifies the three behaviours the seat feature depends on:
///   * `guestCount < 2` → selector renders nothing (solo diner has nothing
///     to split, and a one-chip "Shared" row would be useless).
///   * `guestCount = N ≥ 2` → `N + 1` chips render ("Shared" + 1..N).
///   * Tapping a chip updates [waiterCurrentSeatProvider] so subsequent
///     quick-adds are tagged with that cover.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/waiter/presentation/providers/waiter_provider.dart';
import 'package:gastrocore_pos/features/waiter/presentation/screens/waiter_menu_screen.dart';

/// Minimal draft ticket with the requested [guestCount].
TicketEntity _ticket({required int guestCount}) {
  return TicketEntity(
    id: 'ticket-test-1',
    tenantId: 'tenant-test',
    orderNumber: 'T-0001',
    orderType: OrderType.dineIn,
    tableId: 'table-1',
    guestCount: guestCount,
    status: TicketStatus.draft,
    channel: OrderChannel.waiter,
    openedAt: DateTime(2026, 4, 18),
    deviceId: 'DEV-1',
  );
}

/// Test notifier that starts with the caller-supplied ticket. The real
/// [WaiterActiveTicketNotifier] pulls state via its service; that service
/// has no role in the seat selector's rendering path, so it's safe for the
/// stub to skip the load phase entirely.
class _StubActiveTicketNotifier extends WaiterActiveTicketNotifier {
  _StubActiveTicketNotifier(super.ref, TicketEntity? initial) {
    state = initial;
  }
}

Widget _harness({required TicketEntity? ticket}) {
  return ProviderScope(
    overrides: [
      waiterActiveTicketProvider.overrideWith(
        (ref) => _StubActiveTicketNotifier(ref, ticket),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SeatSelector(),
      ),
    ),
  );
}

void main() {
  group('SeatSelector', () {
    testWidgets('renders nothing when there is no active ticket',
        (tester) async {
      await tester.pumpWidget(_harness(ticket: null));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('waiter.seatSelector')), findsNothing,
          reason: 'no ticket means nothing to tag — selector must hide');
    });

    testWidgets('renders nothing for solo diner (guestCount=1)',
        (tester) async {
      await tester.pumpWidget(_harness(ticket: _ticket(guestCount: 1)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('waiter.seatSelector')), findsNothing,
          reason: 'one-seat tables have nothing to split');
      expect(find.text('Shared'), findsNothing);
    });

    testWidgets('renders Shared + guestCount chips for a 2-top',
        (tester) async {
      await tester.pumpWidget(_harness(ticket: _ticket(guestCount: 2)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('waiter.seatSelector')), findsOneWidget);
      expect(find.text('Shared'), findsOneWidget);
      expect(find.text('Seat 1'), findsOneWidget);
      expect(find.text('Seat 2'), findsOneWidget);
      expect(find.text('Seat 3'), findsNothing);
    });

    testWidgets('renders all chips for a 6-top', (tester) async {
      await tester.pumpWidget(_harness(ticket: _ticket(guestCount: 6)));
      await tester.pumpAndSettle();

      expect(find.text('Shared'), findsOneWidget);
      for (var i = 1; i <= 6; i++) {
        expect(find.text('Seat $i'), findsOneWidget,
            reason: 'seat $i chip must render');
      }
      expect(find.text('Seat 7'), findsNothing);
    });

    testWidgets('tapping a seat chip updates waiterCurrentSeatProvider',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          waiterActiveTicketProvider.overrideWith(
            (ref) => _StubActiveTicketNotifier(ref, _ticket(guestCount: 3)),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SeatSelector()),
        ),
      ));
      await tester.pumpAndSettle();

      // Default seat before any tap is 0 (Shared).
      expect(container.read(waiterCurrentSeatProvider), 0);

      await tester.tap(find.text('Seat 2'));
      await tester.pumpAndSettle();

      expect(container.read(waiterCurrentSeatProvider), 2,
          reason: 'tapping Seat 2 must flip the active-seat state');
    });
  });
}
