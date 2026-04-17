import 'dart:convert';

import 'package:gastrocore_api/gastrocore_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('GastrocoreClient', () {
    test('exposes the expected endpoint groups', () {
      final client = GastrocoreClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      addTearDown(client.dispose);

      expect(client.auth, isA<AuthEndpoint>());
      expect(client.menu, isA<MenuEndpoint>());
      expect(client.orders, isA<OrdersEndpoint>());
      expect(client.tables, isA<TablesEndpoint>());
      expect(client.sync, isA<SyncEndpoint>());
    });

    test('auth token toggles authenticated state and header', () async {
      late Map<String, String> capturedHeaders;
      final mock = MockClient((request) async {
        capturedHeaders = request.headers;
        return http.Response('{"ok":true}', 200);
      });

      final client = GastrocoreClient(
        baseUrl: 'https://example.test',
        httpClient: mock,
      );
      addTearDown(client.dispose);

      expect(client.isAuthenticated, isFalse);
      client.setAuthToken('abc.def.ghi');
      expect(client.isAuthenticated, isTrue);

      await client.get('/ping');
      expect(capturedHeaders['Authorization'], 'Bearer abc.def.ghi');

      client.clearAuthToken();
      expect(client.isAuthenticated, isFalse);
    });

    test('4xx error body is mapped to ApiException', () async {
      final mock = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'message': 'Invalid credentials',
            'code': 'AUTH_BAD',
          }),
          401,
        );
      });

      final client = GastrocoreClient(
        baseUrl: 'https://example.test',
        httpClient: mock,
      );
      addTearDown(client.dispose);

      expect(
        () => client.get('/whoami'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.errorCode, 'errorCode', 'AUTH_BAD')
              .having((e) => e.message, 'message', 'Invalid credentials'),
        ),
      );
    });

    test('getList unwraps a { data: [...] } envelope', () async {
      final mock = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'a'},
              {'id': 'b'},
            ],
          }),
          200,
        );
      });

      final client = GastrocoreClient(
        baseUrl: 'https://example.test',
        httpClient: mock,
      );
      addTearDown(client.dispose);

      final list = await client.getList('/items');
      expect(list, hasLength(2));
      expect((list.first as Map)['id'], 'a');
    });
  });
}
