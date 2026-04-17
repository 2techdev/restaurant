/// Unit tests for [ServiceCallEntity] helpers.
///
/// Guards the enum-string round trip that both the outbox and the receiving
/// dashboard rely on.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/waiter/domain/entities/service_call_entity.dart';

void main() {
  group('ServiceCallKind', () {
    test('round-trips through string form for every canonical kind', () {
      for (final kind in ServiceCallKind.values) {
        final round = parseServiceCallKind(serviceCallKindToString(kind));
        expect(round, kind,
            reason: 'kind ${kind.name} must survive encode/decode');
      }
    });

    test('unknown kind string falls back to "other"', () {
      expect(parseServiceCallKind('rice-wine'), ServiceCallKind.other);
    });

    test('labels are non-empty human strings', () {
      for (final kind in ServiceCallKind.values) {
        expect(serviceCallKindLabel(kind), isNotEmpty);
      }
    });
  });

  group('ServiceCallStatus', () {
    test('round-trips through string form for every status', () {
      for (final s in ServiceCallStatus.values) {
        expect(
          parseServiceCallStatus(serviceCallStatusToString(s)),
          s,
        );
      }
    });

    test('unknown status string falls back to pending', () {
      expect(parseServiceCallStatus('queued'), ServiceCallStatus.pending);
    });
  });

  group('ServiceCallEntity.copyWith', () {
    test('nullable setter wrappers let callers clear fields', () {
      final base = ServiceCallEntity(
        id: 'c1',
        tenantId: 't1',
        waiterId: 'w1',
        waiterName: 'Luca',
        kind: ServiceCallKind.water,
        tableId: 'T-3',
        note: 'ice please',
        createdAt: DateTime(2026, 4, 17, 12),
      );
      final cleared = base.copyWith(
        tableId: () => null,
        note: () => null,
      );
      expect(cleared.tableId, isNull);
      expect(cleared.note, isNull);
      // Unrelated fields preserved.
      expect(cleared.waiterName, 'Luca');
    });

    test('scalar params override only the given field', () {
      final base = ServiceCallEntity(
        id: 'c1',
        tenantId: 't1',
        waiterId: 'w1',
        waiterName: 'Luca',
        kind: ServiceCallKind.water,
        createdAt: DateTime(2026, 4, 17, 12),
      );
      final next = base.copyWith(
        status: ServiceCallStatus.acknowledged,
        acknowledgedBy: () => 'mgr-1',
      );
      expect(next.status, ServiceCallStatus.acknowledged);
      expect(next.acknowledgedBy, 'mgr-1');
      expect(next.kind, ServiceCallKind.water);
    });
  });
}
