import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/features/lan_sync/lan_sync_models.dart';

void main() {
  group('SyncMessage', () {
    late SyncMessage message;

    setUp(() {
      message = SyncMessage(
        id: 'msg-001',
        type: 'sync_event',
        deviceId: 'DEV-POS-01',
        tenantId: 'tenant-abc',
        tableName: 'tickets',
        recordId: 'ticket-xyz',
        operation: 'update',
        payload: {'status': 'served', 'total': 4200},
        vectorClock: VectorClock({'DEV-POS-01': 3, 'DEV-WAITER-01': 1}),
        createdAt: DateTime.utc(2024, 6, 15, 12, 30, 0),
      );
    });

    test('toJson produces correct keys', () {
      final json = message.toJson();
      expect(json['id'], 'msg-001');
      expect(json['type'], 'sync_event');
      expect(json['device_id'], 'DEV-POS-01');
      expect(json['tenant_id'], 'tenant-abc');
      expect(json['table_name'], 'tickets');
      expect(json['record_id'], 'ticket-xyz');
      expect(json['operation'], 'update');
      expect(json['payload'], {'status': 'served', 'total': 4200});
      expect(json['vector_clock'], {'DEV-POS-01': 3, 'DEV-WAITER-01': 1});
    });

    test('fromJson round-trips correctly', () {
      final json = message.toJson();
      final restored = SyncMessage.fromJson(json);

      expect(restored.id, message.id);
      expect(restored.type, message.type);
      expect(restored.deviceId, message.deviceId);
      expect(restored.tenantId, message.tenantId);
      expect(restored.tableName, message.tableName);
      expect(restored.recordId, message.recordId);
      expect(restored.operation, message.operation);
      expect(restored.payload, message.payload);
      expect(restored.vectorClock.entries, message.vectorClock.entries);
      expect(restored.createdAt, message.createdAt);
    });

    test('toSseData produces valid SSE format', () {
      final sse = message.toSseData();
      expect(sse, startsWith('data: '));
      expect(sse, endsWith('\n\n'));

      // The data portion should be valid JSON.
      final dataLine = sse.replaceFirst('data: ', '').trim();
      final decoded = jsonDecode(dataLine) as Map<String, dynamic>;
      expect(decoded['id'], 'msg-001');
    });

    test('fromJson with missing optional fields uses defaults', () {
      final minimal = <String, dynamic>{
        'id': 'x',
        'device_id': 'dev',
        'tenant_id': 'ten',
        'table_name': 'orders',
        'record_id': 'r1',
        'operation': 'insert',
        'payload': <String, dynamic>{},
      };

      final msg = SyncMessage.fromJson(minimal);
      expect(msg.type, 'sync_event');
      expect(msg.vectorClock.entries, isEmpty);
    });
  });

  group('SyncPeer', () {
    test('baseUrl is constructed from ipAddress and port', () {
      const peer = SyncPeer(
        deviceId: 'dev1',
        deviceName: 'POS-1',
        ipAddress: '192.168.1.42',
        port: 52374,
        role: DeviceRole.primary,
        status: PeerConnectionStatus.connected,
      );
      expect(peer.baseUrl, 'http://192.168.1.42:52374');
    });

    test('toJson / fromJson round-trips', () {
      const peer = SyncPeer(
        deviceId: 'dev1',
        deviceName: 'POS-Main',
        ipAddress: '10.0.0.5',
        port: 8080,
        role: DeviceRole.secondary,
        status: PeerConnectionStatus.discovered,
        tenantId: 'tenant-1',
      );

      final json = peer.toJson();
      final restored = SyncPeer.fromJson(json);

      expect(restored.deviceId, peer.deviceId);
      expect(restored.deviceName, peer.deviceName);
      expect(restored.ipAddress, peer.ipAddress);
      expect(restored.port, peer.port);
      expect(restored.role, peer.role);
      expect(restored.tenantId, peer.tenantId);
    });

    test('copyWith overrides only specified fields', () {
      const original = SyncPeer(
        deviceId: 'dev1',
        deviceName: 'POS-1',
        ipAddress: '10.0.0.1',
        port: 80,
        role: DeviceRole.secondary,
        status: PeerConnectionStatus.discovered,
      );

      final updated = original.copyWith(status: PeerConnectionStatus.connected);
      expect(updated.status, PeerConnectionStatus.connected);
      expect(updated.deviceId, original.deviceId);
      expect(updated.ipAddress, original.ipAddress);
    });
  });

  group('HandshakeRequest / HandshakeResponse', () {
    test('HandshakeRequest round-trips', () {
      final req = HandshakeRequest(
        deviceId: 'dev-a',
        deviceName: 'Waiter-1',
        tenantId: 'tenant-1',
        role: DeviceRole.secondary,
        vectorClock: VectorClock({'dev-a': 5}),
        lastSyncCursor: 'cursor-abc',
      );

      final restored = HandshakeRequest.fromJson(req.toJson());
      expect(restored.deviceId, req.deviceId);
      expect(restored.role, DeviceRole.secondary);
      expect(restored.lastSyncCursor, 'cursor-abc');
      expect(restored.vectorClock.entries, {'dev-a': 5});
    });

    test('HandshakeResponse round-trips', () {
      final res = HandshakeResponse(
        primaryDeviceId: 'primary-1',
        primaryDeviceName: 'POS-Main',
        tenantId: 'tenant-1',
        syncCursor: 'cursor-xyz',
        vectorClock: VectorClock({'primary-1': 10}),
        sseEndpoint: '/sync/events',
        acceptedAt: DateTime.utc(2024, 1, 1),
      );

      final restored = HandshakeResponse.fromJson(res.toJson());
      expect(restored.primaryDeviceId, 'primary-1');
      expect(restored.syncCursor, 'cursor-xyz');
      expect(restored.sseEndpoint, '/sync/events');
      expect(restored.vectorClock.entries['primary-1'], 10);
    });
  });
}
