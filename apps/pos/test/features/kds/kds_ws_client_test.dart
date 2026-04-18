/// Tests for the KDS WebSocket client's JSON parsing layer.
///
/// The connection / reconnect loops are integration-level and exercised in
/// manual QA. These tests lock down the wire format so server-side JSON
/// changes can't silently break the KDS notification pipeline.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/features/kds_app/data/kds_ws_client.dart';

void main() {
  group('KdsEvent.fromJson', () {
    test('parses a new_ticket payload', () {
      final event = KdsEvent.fromJson({
        'type': 'new_ticket',
        'ticket_id': 't-42',
        'order_number': '1007',
      });
      expect(event.type, 'new_ticket');
      expect(event.ticketId, 't-42');
      expect(event.orderNumber, '1007');
      expect(event.status, isNull);
    });

    test('parses a status_update payload', () {
      final event = KdsEvent.fromJson({
        'type': 'status_update',
        'ticket_id': 't-42',
        'status': 'preparing',
      });
      expect(event.type, 'status_update');
      expect(event.status, 'preparing');
    });

    test('parses a ticket_closed payload', () {
      final event = KdsEvent.fromJson({
        'type': 'ticket_closed',
        'ticket_id': 't-42',
      });
      expect(event.type, 'ticket_closed');
      expect(event.ticketId, 't-42');
    });

    test('defaults type to "unknown" when missing', () {
      final event = KdsEvent.fromJson({'ticket_id': 't-42'});
      expect(event.type, 'unknown');
      expect(event.ticketId, 't-42');
    });

    test('tolerates absent optional fields', () {
      final event = KdsEvent.fromJson({'type': 'new_ticket'});
      expect(event.type, 'new_ticket');
      expect(event.ticketId, isNull);
      expect(event.orderNumber, isNull);
      expect(event.status, isNull);
    });

    test('stamps receivedAt close to now()', () {
      final before = DateTime.now();
      final event = KdsEvent.fromJson({'type': 'new_ticket'});
      final after = DateTime.now();
      expect(
        event.receivedAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        event.receivedAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });

  group('KdsWsClient lifecycle', () {
    test('starts in disconnected state', () {
      final client = KdsWsClient(
        baseUrl: 'http://example.invalid:0',
        tenantId: 't',
        deviceId: 'd',
        onEvent: (_) {},
      );
      expect(client.state, KdsWsState.disconnected);
      client.dispose();
    });

    test('dispose() is idempotent and leaves state disconnected', () {
      final client = KdsWsClient(
        baseUrl: 'http://example.invalid:0',
        tenantId: 't',
        deviceId: 'd',
        onEvent: (_) {},
      );
      client.dispose();
      client.dispose();
      expect(client.state, KdsWsState.disconnected);
    });
  });
}
