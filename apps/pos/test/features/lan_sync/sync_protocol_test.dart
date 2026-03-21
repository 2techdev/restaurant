import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/features/lan_sync/lan_sync_models.dart';
import 'package:gastrocore_pos/features/lan_sync/sync_protocol.dart';

void main() {
  const protocol = SyncProtocol();

  // ---------------------------------------------------------------------------
  // VectorClock
  // ---------------------------------------------------------------------------

  group('VectorClock', () {
    test('starts empty', () {
      final clock = VectorClock();
      expect(clock.entries, isEmpty);
    });

    test('increment adds device entry', () {
      final clock = VectorClock();
      clock.increment('A');
      expect(clock.entries['A'], 1);
    });

    test('increment is monotone', () {
      final clock = VectorClock();
      clock.increment('A');
      clock.increment('A');
      clock.increment('A');
      expect(clock.entries['A'], 3);
    });

    test('merge takes element-wise max', () {
      final a = VectorClock({'A': 3, 'B': 1});
      final b = VectorClock({'A': 1, 'B': 5, 'C': 2});
      final merged = a.merge(b);
      expect(merged.entries['A'], 3);
      expect(merged.entries['B'], 5);
      expect(merged.entries['C'], 2);
    });

    group('compareTo', () {
      test('returns 1 when this is strictly after', () {
        final old = VectorClock({'A': 1});
        final newer = VectorClock({'A': 2});
        expect(newer.compareTo(old), 1);
      });

      test('returns -1 when this is strictly before', () {
        final old = VectorClock({'A': 1});
        final newer = VectorClock({'A': 2});
        expect(old.compareTo(newer), -1);
      });

      test('returns 0 for concurrent (neither dominates)', () {
        final a = VectorClock({'A': 2, 'B': 1});
        final b = VectorClock({'A': 1, 'B': 2});
        expect(a.compareTo(b), 0);
      });

      test('returns 0 for equal clocks', () {
        final a = VectorClock({'A': 1});
        final b = VectorClock({'A': 1});
        expect(a.compareTo(b), 0);
      });

      test('treats missing key as 0', () {
        final a = VectorClock({'A': 1});
        final b = VectorClock({'A': 1, 'B': 1});
        // b has 'B': 1, a has 'B': 0 → b is ahead
        expect(a.compareTo(b), -1);
      });
    });

    test('toJson / fromJson round-trips', () {
      final original = VectorClock({'A': 3, 'B': 7});
      final json = original.toJson();
      final restored = VectorClock.fromJson(json);
      expect(restored.entries, original.entries);
    });
  });

  // ---------------------------------------------------------------------------
  // SyncProtocol.resolve
  // ---------------------------------------------------------------------------

  SyncMessage makeMessage({
    String id = 'msg1',
    String deviceId = 'DEV-A',
    String recordId = 'rec1',
    String tableName = 'tickets',
    String operation = 'update',
    Map<String, dynamic>? payload,
    VectorClock? clock,
    DateTime? createdAt,
  }) {
    return SyncMessage(
      id: id,
      type: 'sync_event',
      deviceId: deviceId,
      tenantId: 'tenant1',
      tableName: tableName,
      recordId: recordId,
      operation: operation,
      payload: payload ?? {},
      vectorClock: clock ?? VectorClock(),
      createdAt: createdAt ?? DateTime.now().toUtc(),
    );
  }

  group('SyncProtocol.resolve', () {
    test('causally later message wins', () {
      final local = makeMessage(
        clock: VectorClock({'A': 1}),
        createdAt: DateTime(2024, 1, 1, 10, 0),
      );
      final remote = makeMessage(
        deviceId: 'DEV-B',
        clock: VectorClock({'A': 1, 'B': 1}), // remote is after local
        createdAt: DateTime(2024, 1, 1, 9, 0), // older wall clock, but later vector
      );

      final conflict = protocol.resolve(local, remote);
      expect(conflict.resolution, ConflictResolution.remoteWins);
      expect(conflict.resolvedMessage.deviceId, 'DEV-B');
    });

    test('causally earlier remote loses', () {
      final local = makeMessage(
        clock: VectorClock({'A': 2}),
      );
      final remote = makeMessage(
        deviceId: 'DEV-B',
        clock: VectorClock({'A': 1}),
      );

      final conflict = protocol.resolve(local, remote);
      expect(conflict.resolution, ConflictResolution.localWins);
    });

    test('concurrent — delete beats update', () {
      final updateMsg = makeMessage(
        operation: 'update',
        clock: VectorClock({'A': 1}),
      );
      final deleteMsg = makeMessage(
        deviceId: 'DEV-B',
        operation: 'delete',
        clock: VectorClock({'B': 1}), // concurrent
      );

      final conflict = protocol.resolve(updateMsg, deleteMsg);
      expect(conflict.resolution, ConflictResolution.remoteWins);
      expect(conflict.resolvedMessage.operation, 'delete');
    });

    test('concurrent — local delete beats remote update', () {
      final deleteMsg = makeMessage(
        operation: 'delete',
        clock: VectorClock({'A': 1}),
      );
      final updateMsg = makeMessage(
        deviceId: 'DEV-B',
        operation: 'update',
        clock: VectorClock({'B': 1}), // concurrent
      );

      final conflict = protocol.resolve(deleteMsg, updateMsg);
      expect(conflict.resolution, ConflictResolution.localWins);
    });

    test('concurrent updates — last-write-wins by wall clock', () {
      final older = makeMessage(
        deviceId: 'DEV-A',
        clock: VectorClock({'A': 1}),
        createdAt: DateTime(2024, 1, 1, 9, 0),
      );
      final newer = makeMessage(
        deviceId: 'DEV-B',
        clock: VectorClock({'B': 1}), // concurrent
        createdAt: DateTime(2024, 1, 1, 10, 0),
      );

      final conflict = protocol.resolve(older, newer);
      expect(conflict.resolution, ConflictResolution.remoteWins);
      expect(conflict.resolvedMessage.deviceId, 'DEV-B');
    });

    test('same wall clock — local wins as tie-break', () {
      final ts = DateTime(2024, 1, 1, 10, 0);
      final local = makeMessage(clock: VectorClock({'A': 1}), createdAt: ts);
      final remote = makeMessage(
        deviceId: 'DEV-B',
        clock: VectorClock({'B': 1}),
        createdAt: ts,
      );

      final conflict = protocol.resolve(local, remote);
      // !remote.createdAt.isAfter(local.createdAt) → local wins
      expect(conflict.resolution, ConflictResolution.localWins);
    });
  });

  // ---------------------------------------------------------------------------
  // SyncProtocol.mergeIncoming
  // ---------------------------------------------------------------------------

  group('SyncProtocol.mergeIncoming', () {
    test('new records are always applied', () {
      final incoming = [makeMessage(recordId: 'new-rec')];
      final result = protocol.mergeIncoming(
        incoming: incoming,
        localState: {},
      );
      expect(result, hasLength(1));
      expect(result.first.recordId, 'new-rec');
    });

    test('conflicting record applies winner only', () {
      final local = makeMessage(
        recordId: 'rec1',
        clock: VectorClock({'A': 3}), // local is ahead
        createdAt: DateTime(2024, 1, 1, 12),
      );
      final remote = makeMessage(
        recordId: 'rec1',
        clock: VectorClock({'A': 1}), // remote is behind
        createdAt: DateTime(2024, 1, 1, 11),
      );

      final result = protocol.mergeIncoming(
        incoming: [remote],
        localState: {'rec1': local},
      );
      // Local wins → remote should NOT be applied.
      expect(result, isEmpty);
    });

    test('multiple records mixed new and conflict', () {
      final localRec = makeMessage(
        recordId: 'rec1',
        clock: VectorClock({'A': 5}),
      );
      final incoming = [
        makeMessage(recordId: 'rec1', clock: VectorClock({'A': 2})), // loses
        makeMessage(recordId: 'rec2'), // new
        makeMessage(recordId: 'rec3'), // new
      ];

      final result = protocol.mergeIncoming(
        incoming: incoming,
        localState: {'rec1': localRec},
      );

      expect(result.map((m) => m.recordId).toList(), ['rec2', 'rec3']);
    });
  });

  // ---------------------------------------------------------------------------
  // SyncProtocol.advance
  // ---------------------------------------------------------------------------

  group('SyncProtocol.advance', () {
    test('increments device counter', () {
      final base = VectorClock({'A': 2, 'B': 1});
      final advanced = protocol.advance(base, 'A');
      expect(advanced.entries['A'], 3);
      expect(advanced.entries['B'], 1);
    });

    test('does not mutate original clock', () {
      final base = VectorClock({'A': 1});
      protocol.advance(base, 'A');
      expect(base.entries['A'], 1); // unchanged
    });
  });
}
