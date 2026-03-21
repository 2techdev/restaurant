import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/features/fiscal_de/fiskaly_models.dart';

void main() {
  group('FiskalyConfig', () {
    test('isConfigured is false when empty', () {
      expect(FiskalyConfig.empty().isConfigured, isFalse);
    });

    test('isConfigured is true when credentials present', () {
      const cfg = FiskalyConfig(apiKey: 'key', apiSecret: 'secret');
      expect(cfg.isConfigured, isTrue);
    });

    test('roundtrips through JSON', () {
      const cfg = FiskalyConfig(
        apiKey: 'my-api-key',
        apiSecret: 'my-api-secret',
        environment: 'production',
        tseId: 'tse-uuid',
        clientId: 'client-uuid',
        adminPin: '99999',
      );
      final json = cfg.toJsonString();
      final restored = FiskalyConfig.fromJsonString(json);

      expect(restored.apiKey, equals('my-api-key'));
      expect(restored.apiSecret, equals('my-api-secret'));
      expect(restored.environment, equals('production'));
      expect(restored.tseId, equals('tse-uuid'));
      expect(restored.clientId, equals('client-uuid'));
      expect(restored.adminPin, equals('99999'));
    });

    test('copyWith replaces only specified fields', () {
      const original = FiskalyConfig(
        apiKey: 'key',
        apiSecret: 'secret',
        tseId: 'tse-id',
      );
      final copy = original.copyWith(tseId: 'new-tse');
      expect(copy.apiKey, equals('key'));
      expect(copy.tseId, equals('new-tse'));
    });

    test('fromJson handles missing fields with defaults', () {
      final cfg = FiskalyConfig.fromJson({});
      expect(cfg.apiKey, equals(''));
      expect(cfg.apiSecret, equals(''));
      expect(cfg.environment, equals('test'));
      expect(cfg.tseId, isNull);
      expect(cfg.clientId, isNull);
      expect(cfg.adminPin, equals('12345'));
    });
  });

  group('TseInfo.fromJson', () {
    test('parses ACTIVE state', () {
      final info = TseInfo.fromJson({
        '_id': 'tse-abc',
        'state': 'ACTIVE',
        'serial_number': 'DEADBEEF',
        'signature_algorithm': 'ecdsa-plain-SHA384',
        'signature_counter': 100,
      });
      expect(info.id, equals('tse-abc'));
      expect(info.state, equals(TseState.active));
      expect(info.serialNumber, equals('DEADBEEF'));
      expect(info.signatureAlgorithm, equals('ecdsa-plain-SHA384'));
      expect(info.signatureCounter, equals(100));
    });

    test('parses INITIALIZED state', () {
      final info = TseInfo.fromJson({'state': 'INITIALIZED'});
      expect(info.state, equals(TseState.initialized));
    });

    test('parses DISABLED state', () {
      final info = TseInfo.fromJson({'state': 'DISABLED'});
      expect(info.state, equals(TseState.disabled));
    });

    test('unknown state maps to unknown', () {
      final info = TseInfo.fromJson({'state': 'BOGUS'});
      expect(info.state, equals(TseState.unknown));
    });

    test('uses id fallback when _id is absent', () {
      final info = TseInfo.fromJson({'id': 'fallback-id', 'state': 'ACTIVE'});
      expect(info.id, equals('fallback-id'));
    });
  });

  group('TseSignatureData', () {
    final sampleJson = {
      'transaction_number': 42,
      'time_start': '2024-01-15T10:00:00Z',
      'time_end': '2024-01-15T10:00:01Z',
      'process_type': 'Kassenbeleg-V1',
      'process_data': 'Beleg^0.00_0.00_23.80^23.80:Bar',
      'signature': {
        'value': 'ABCDEF1234',
        'signature_counter': 99,
        'algorithm': 'ecdsa-plain-SHA384',
      },
      'tse': {
        'serial_number': 'DEADBEEF',
        'signature_algorithm': 'ecdsa-plain-SHA384',
        'public_key': 'BASE64PUB',
      },
    };

    test('parses all required fields', () {
      final sig = TseSignatureData.fromJson(sampleJson);
      expect(sig.transactionNumber, equals(42));
      expect(sig.signatureCounter, equals(99));
      expect(sig.signatureValue, equals('ABCDEF1234'));
      expect(sig.tseSerialNumber, equals('DEADBEEF'));
      expect(sig.algorithm, equals('ecdsa-plain-SHA384'));
      expect(sig.processType, equals('Kassenbeleg-V1'));
    });

    test('roundtrips through toJson', () {
      final sig = TseSignatureData.fromJson(sampleJson);
      final json = sig.toJson();
      expect(json['transaction_number'], equals(42));
      expect(json['signature_value'], equals('ABCDEF1234'));
      expect(json['tse_serial_number'], equals('DEADBEEF'));
    });
  });

  group('ExportState.fromJson', () {
    test('parses PENDING state', () {
      final es = ExportState.fromJson({'_id': 'exp-1', 'state': 'PENDING'});
      expect(es.id, equals('exp-1'));
      expect(es.isPending, isTrue);
      expect(es.isCompleted, isFalse);
    });

    test('parses COMPLETED state with href', () {
      final es = ExportState.fromJson({
        '_id': 'exp-2',
        'state': 'COMPLETED',
        'href': 'https://example.com/export.tar',
      });
      expect(es.isCompleted, isTrue);
      expect(es.href, equals('https://example.com/export.tar'));
    });

    test('parses FAILED state', () {
      final es = ExportState.fromJson({
        '_id': 'exp-3',
        'state': 'FAILED',
        'error': 'TSE error',
      });
      expect(es.isFailed, isTrue);
      expect(es.error, equals('TSE error'));
    });
  });

  group('parseTseState', () {
    test('parses all known states case-insensitively', () {
      expect(parseTseState('CREATED'), equals(TseState.created));
      expect(parseTseState('created'), equals(TseState.created));
      expect(parseTseState('INITIALIZED'), equals(TseState.initialized));
      expect(parseTseState('ACTIVE'), equals(TseState.active));
      expect(parseTseState('DISABLED'), equals(TseState.disabled));
      expect(parseTseState(null), equals(TseState.unknown));
      expect(parseTseState(''), equals(TseState.unknown));
    });
  });
}
