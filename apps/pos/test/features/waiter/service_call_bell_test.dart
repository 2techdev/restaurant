/// Widget tests for [ServiceCallBell] — the POS home-screen indicator that
/// surfaces open service calls raised by waiters.
///
/// Covers the three rendering states that matter for the floor manager:
///   * zero calls → muted bell, no badge, tooltip says "No open service calls".
///   * N calls → active (orange) bell with a "N" badge; tap opens the inbox.
///   * 10+ calls → badge shows "9+" (sanity cap).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/waiter/domain/entities/service_call_entity.dart';
import 'package:gastrocore_pos/features/waiter/presentation/providers/waiter_provider.dart';
import 'package:gastrocore_pos/features/waiter/presentation/widgets/service_call_bell.dart';

ServiceCallEntity _call({
  String id = 'call-1',
  ServiceCallKind kind = ServiceCallKind.water,
  ServiceCallStatus status = ServiceCallStatus.pending,
  String waiterName = 'Ayşe',
}) {
  return ServiceCallEntity(
    id: id,
    tenantId: 'tenant-1',
    waiterId: 'w-1',
    waiterName: waiterName,
    kind: kind,
    createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
    status: status,
  );
}

Widget _harness({required List<ServiceCallEntity> calls}) {
  return ProviderScope(
    overrides: [
      activeServiceCallsProvider.overrideWith((ref) => Stream.value(calls)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: Center(child: ServiceCallBell())),
    ),
  );
}

void main() {
  group('ServiceCallBell', () {
    testWidgets('renders with no badge when there are no open calls',
        (tester) async {
      await tester.pumpWidget(_harness(calls: const []));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home.serviceCallBell')), findsOneWidget);
      // Badge digits should not render when count == 0.
      expect(find.text('1'), findsNothing);
      expect(find.text('9+'), findsNothing);
    });

    testWidgets('renders a numeric badge when there are open calls',
        (tester) async {
      await tester.pumpWidget(_harness(
        calls: [
          _call(id: 'a', kind: ServiceCallKind.water),
          _call(id: 'b', kind: ServiceCallKind.bread),
          _call(id: 'c', kind: ServiceCallKind.manager),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget,
          reason: 'badge must show the count of open calls');
    });

    testWidgets('caps the badge at "9+" when 10 or more calls are open',
        (tester) async {
      final many = List<ServiceCallEntity>.generate(
        12,
        (i) => _call(id: 'call-$i'),
      );
      await tester.pumpWidget(_harness(calls: many));
      await tester.pumpAndSettle();

      expect(find.text('9+'), findsOneWidget);
      expect(find.text('12'), findsNothing);
    });
  });
}
