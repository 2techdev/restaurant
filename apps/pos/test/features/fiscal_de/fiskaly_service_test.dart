import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:gastrocore_pos/features/fiscal_de/fiskaly_models.dart';
import 'package:gastrocore_pos/features/fiscal_de/fiskaly_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// ignore: unused_element
http.Client _mockClient(Map<String, Map<String, dynamic>> responses) {
  return MockClient((request) async {
    final path = request.url.path;
    for (final entry in responses.entries) {
      if (path.contains(entry.key)) {
        return http.Response(jsonEncode(entry.value), 200,
            headers: {'content-type': 'application/json'});
      }
    }
    return http.Response('{"error":"not found"}', 404);
  });
}

http.Client _authClient({int statusCode = 200}) {
  return MockClient((request) async {
    if (request.url.path.contains('/auth')) {
      if (statusCode != 200) {
        return http.Response('{"error":"unauthorized"}', statusCode);
      }
      return http.Response(
        jsonEncode({
          'access_token': 'test-jwt',
          'access_token_expires_in_seconds': 3600,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({
        '_id': 'tse-id',
        'state': 'ACTIVE',
        'serial_number': 'DEADBEEF',
        'signature_algorithm': 'ecdsa-plain-SHA384',
        'signature_counter': 0,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

const _config = FiskalyConfig(
  apiKey: 'test-key',
  apiSecret: 'test-secret',
  tseId: 'tse-uuid',
  clientId: 'client-uuid',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FiskalyService — authenticate', () {
    test('returns token on success', () async {
      final service =
          FiskalyService(config: _config, client: _authClient());
      final token = await service.authenticate();
      expect(token, equals('test-jwt'));
    });

    test('throws FiskalyException on 401', () async {
      final service = FiskalyService(
        config: _config,
        client: _authClient(statusCode: 401),
      );
      expect(
        () => service.authenticate(),
        throwsA(isA<FiskalyException>()),
      );
    });

    test('caches token and does not re-authenticate', () async {
      var callCount = 0;
      final client = MockClient((request) async {
        if (request.url.path.contains('/auth')) callCount++;
        return http.Response(
          jsonEncode({
            'access_token': 'cached-token',
            'access_token_expires_in_seconds': 3600,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = FiskalyService(config: _config, client: client);
      await service.authenticate();
      await service.authenticate(); // second call — should use cache
      expect(callCount, equals(1));
    });

    test('invalidateToken forces re-authentication', () async {
      var callCount = 0;
      final client = MockClient((request) async {
        if (request.url.path.contains('/auth')) callCount++;
        return http.Response(
          jsonEncode({
            'access_token': 'token',
            'access_token_expires_in_seconds': 3600,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = FiskalyService(config: _config, client: client);
      await service.authenticate();
      service.invalidateToken();
      await service.authenticate();
      expect(callCount, equals(2));
    });
  });

  group('FiskalyService — getTseInfo', () {
    test('returns TseInfo on success', () async {
      final client = _authClient();
      final service = FiskalyService(config: _config, client: client);
      final info = await service.getTseInfo('tse-uuid');
      expect(info.id, equals('tse-id'));
      expect(info.state, equals(TseState.active));
      expect(info.serialNumber, equals('DEADBEEF'));
    });
  });

  group('FiskalyService — startTransaction', () {
    test('sends correct body and returns transaction', () async {
      String? capturedBody;
      final client = MockClient((request) async {
        if (request.url.path.contains('/auth')) {
          return http.Response(
            jsonEncode({
              'access_token': 'tok',
              'access_token_expires_in_seconds': 3600,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        capturedBody = request.body;
        return http.Response(
          jsonEncode({
            '_id': 'tx-id',
            'transaction_number': 1,
            'state': 'ACTIVE',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = FiskalyService(config: _config, client: client);
      final tx = await service.startTransaction(
        tseId: 'tse-uuid',
        transactionId: 'tx-abc',
        clientId: 'client-uuid',
      );

      expect(tx.state, equals('ACTIVE'));
      expect(tx.transactionNumber, equals(1));
      expect(capturedBody, contains('"state":"ACTIVE"'));
      expect(capturedBody, contains('"client_id":"client-uuid"'));
    });
  });

  group('FiskalyService — triggerExport', () {
    test('returns ExportState with PENDING', () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/auth')) {
          return http.Response(
            jsonEncode({
              'access_token': 'tok',
              'access_token_expires_in_seconds': 3600,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'_id': 'export-123', 'state': 'PENDING'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = FiskalyService(config: _config, client: client);
      final export = await service.triggerExport('tse-uuid');
      expect(export.id, equals('export-123'));
      expect(export.isPending, isTrue);
    });
  });

  group('FiskalyException', () {
    test('toString includes statusCode', () {
      const e = FiskalyException('test error', statusCode: 422);
      expect(e.toString(), contains('422'));
      expect(e.toString(), contains('test error'));
    });
  });
}
