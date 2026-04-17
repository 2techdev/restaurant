import 'package:gastrocore_models/gastrocore_models.dart';
import 'package:test/test.dart';

void main() {
  group('SyncEventEntity', () {
    test('fromJson / toJson round-trip preserves every field', () {
      final original = SyncEventEntity(
        id: 42,
        tableName: 'tickets',
        operation: SyncOperation.update,
        recordId: 'ticket-1',
        payload: '{"total":1500}',
        createdAt: DateTime.utc(2026, 4, 17, 12, 0, 0),
        deviceId: 'pos-1',
        syncedAt: DateTime.utc(2026, 4, 17, 12, 0, 5),
        status: SyncEventStatus.uploaded,
        retryCount: 1,
        errorMessage: null,
      );

      final json = original.toJson();
      final revived = SyncEventEntity.fromJson(json);

      expect(revived.id, original.id);
      expect(revived.tableName, original.tableName);
      expect(revived.operation, original.operation);
      expect(revived.recordId, original.recordId);
      expect(revived.payload, original.payload);
      expect(revived.createdAt, original.createdAt);
      expect(revived.deviceId, original.deviceId);
      expect(revived.syncedAt, original.syncedAt);
      expect(revived.status, original.status);
      expect(revived.retryCount, original.retryCount);
    });

    test('copyWith replaces only provided fields', () {
      final base = SyncEventEntity(
        id: 1,
        tableName: 'orders',
        operation: SyncOperation.insert,
        recordId: 'o1',
        payload: '{}',
        createdAt: DateTime.utc(2026, 4, 17),
        deviceId: 'pos-1',
      );
      final updated = base.copyWith(
        status: SyncEventStatus.failed,
        errorMessage: 'boom',
        retryCount: 2,
      );
      expect(updated.status, SyncEventStatus.failed);
      expect(updated.errorMessage, 'boom');
      expect(updated.retryCount, 2);
      expect(updated.recordId, base.recordId);
      expect(updated.payload, base.payload);
    });
  });
}
