import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/features/lan_sync/endpoints/menu_endpoint.dart';
import 'package:gastrocore_pos/features/lan_sync/endpoints/orders_endpoint.dart';
import 'package:gastrocore_pos/features/lan_sync/endpoints/sync_status_endpoint.dart';
import 'package:gastrocore_pos/features/lan_sync/endpoints/tables_endpoint.dart';
import 'package:shelf/shelf.dart';

void main() {
  // ---------------------------------------------------------------------------
  // OrdersEndpoint
  // ---------------------------------------------------------------------------

  group('OrdersEndpoint', () {
    late OrdersEndpoint endpoint;
    final sampleOrders = [
      {'id': 'ticket-1', 'status': 'open', 'total': 2400},
      {'id': 'ticket-2', 'status': 'served', 'total': 1800},
    ];

    setUp(() {
      endpoint = OrdersEndpoint(
        fetchOrders: ({String since = ''}) async => sampleOrders,
        receiveOrder: (_) async {},
      );
    });

    test('getOrders returns 200 with orders array', () async {
      final request = Request('GET', Uri.parse('http://localhost/orders'));
      final response = await endpoint.getOrders(request);

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['orders'], hasLength(2));
      expect(body['count'], 2);
    });

    test('getOrders passes since parameter', () async {
      String? capturedSince;
      final ep = OrdersEndpoint(
        fetchOrders: ({String since = ''}) async {
          capturedSince = since;
          return [];
        },
        receiveOrder: (_) async {},
      );

      final request = Request(
        'GET',
        Uri.parse('http://localhost/orders?since=2024-01-01T00:00:00Z'),
      );
      await ep.getOrders(request);
      expect(capturedSince, '2024-01-01T00:00:00Z');
    });

    test('postOrder accepts valid JSON and returns 200', () async {
      final order = {'id': 'ticket-new', 'status': 'open', 'total': 500};
      final request = Request(
        'POST',
        Uri.parse('http://localhost/orders'),
        body: jsonEncode(order),
        headers: {'Content-Type': 'application/json'},
      );
      final response = await endpoint.postOrder(request);

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['status'], 'accepted');
    });

    test('postOrder returns 500 on invalid JSON', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/orders'),
        body: 'not-json',
      );
      final response = await endpoint.postOrder(request);
      expect(response.statusCode, 500);
    });

    test('getOrders returns 500 when fetchOrders throws', () async {
      final ep = OrdersEndpoint(
        fetchOrders: ({String since = ''}) async =>
            throw Exception('DB error'),
        receiveOrder: (_) async {},
      );
      final request = Request('GET', Uri.parse('http://localhost/orders'));
      final response = await ep.getOrders(request);
      expect(response.statusCode, 500);
    });
  });

  // ---------------------------------------------------------------------------
  // MenuEndpoint
  // ---------------------------------------------------------------------------

  group('MenuEndpoint', () {
    test('getMenu returns 200 with menu data', () async {
      final endpoint = MenuEndpoint(
        fetchMenu: () async => {
          'categories': [
            {'id': 'cat-1', 'name': 'Starters'},
          ],
          'products': [
            {'id': 'prod-1', 'name': 'Caesar Salad', 'price': 1800},
          ],
        },
      );

      final request = Request('GET', Uri.parse('http://localhost/menu'));
      final response = await endpoint.getMenu(request);

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect((body['categories'] as List).length, 1);
      expect((body['products'] as List).length, 1);
    });

    test('getMenu returns 500 when fetchMenu throws', () async {
      final endpoint = MenuEndpoint(
        fetchMenu: () async => throw Exception('DB error'),
      );
      final request = Request('GET', Uri.parse('http://localhost/menu'));
      final response = await endpoint.getMenu(request);
      expect(response.statusCode, 500);
    });
  });

  // ---------------------------------------------------------------------------
  // TablesEndpoint
  // ---------------------------------------------------------------------------

  group('TablesEndpoint', () {
    final sampleTables = [
      {'id': 'tbl-1', 'name': 'T1', 'status': 'available'},
      {'id': 'tbl-2', 'name': 'T2', 'status': 'occupied'},
    ];

    test('getTables returns 200 with tables array', () async {
      final endpoint = TablesEndpoint(
        fetchTables: () async => sampleTables,
        updateTableStatus: (_) async {},
      );

      final request = Request('GET', Uri.parse('http://localhost/tables'));
      final response = await endpoint.getTables(request);

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['tables'], hasLength(2));
      expect(body['count'], 2);
    });

    test('postTableStatus accepts valid payload', () async {
      Map<String, dynamic>? received;
      final endpoint = TablesEndpoint(
        fetchTables: () async => [],
        updateTableStatus: (json) async => received = json,
      );

      final payload = {'table_id': 'tbl-1', 'status': 'occupied'};
      final request = Request(
        'POST',
        Uri.parse('http://localhost/table-status'),
        body: jsonEncode(payload),
      );
      final response = await endpoint.postTableStatus(request);

      expect(response.statusCode, 200);
      expect(received?['table_id'], 'tbl-1');
    });

    test('postTableStatus returns 400 when required fields are missing',
        () async {
      final endpoint = TablesEndpoint(
        fetchTables: () async => [],
        updateTableStatus: (_) async {},
      );

      final request = Request(
        'POST',
        Uri.parse('http://localhost/table-status'),
        body: jsonEncode({'table_id': 'tbl-1'}), // missing status
      );
      final response = await endpoint.postTableStatus(request);
      expect(response.statusCode, 400);
    });
  });

  // ---------------------------------------------------------------------------
  // SyncStatusEndpoint
  // ---------------------------------------------------------------------------

  group('SyncStatusEndpoint', () {
    test('getStatus returns 200 with correct fields', () async {
      final endpoint = SyncStatusEndpoint(
        primaryDeviceId: 'dev-primary',
        primaryDeviceName: 'POS-Main',
        tenantId: 'tenant-1',
        getCursor: () async => 'cursor-abc',
        getConnectedPeerCount: () => 3,
      );

      final request = Request('GET', Uri.parse('http://localhost/sync/status'));
      final response = await endpoint.getStatus(request);

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['primary_device_id'], 'dev-primary');
      expect(body['tenant_id'], 'tenant-1');
      expect(body['cursor'], 'cursor-abc');
      expect(body['connected_peers'], 3);
      expect(body.containsKey('server_time'), isTrue);
    });

    test('getCurrentCursor delegates to getCursor callback', () async {
      final endpoint = SyncStatusEndpoint(
        primaryDeviceId: 'dev',
        primaryDeviceName: 'POS',
        tenantId: 'tenant',
        getCursor: () async => 'my-cursor',
        getConnectedPeerCount: () => 0,
      );

      final cursor = await endpoint.getCurrentCursor();
      expect(cursor, 'my-cursor');
    });

    test('getStatus returns 500 when getCursor throws', () async {
      final endpoint = SyncStatusEndpoint(
        primaryDeviceId: 'dev',
        primaryDeviceName: 'POS',
        tenantId: 'tenant',
        getCursor: () async => throw Exception('DB offline'),
        getConnectedPeerCount: () => 0,
      );

      final request = Request('GET', Uri.parse('http://localhost/sync/status'));
      final response = await endpoint.getStatus(request);
      expect(response.statusCode, 500);
    });
  });
}
