/// Integration tests for [UpdateService.fetchManifest].
///
/// Covers the error paths the UI layer translates into operator messages:
///   * empty / malformed URL,
///   * non-200 response,
///   * non-JSON body,
///   * happy path.
///
/// Run with:
///   flutter test test/features/updates/update_service_test.dart
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:gastrocore_pos/features/updates/data/update_service.dart';

UpdateService _serviceReturning({
  required int status,
  required String body,
}) {
  final client = MockClient((request) async => http.Response(body, status));
  return UpdateService(client: client);
}

void main() {
  group('UpdateService.fetchManifest', () {
    test('returns a parsed manifest on 200 + valid JSON', () async {
      final service = _serviceReturning(
        status: 200,
        body: jsonEncode({
          'versionName': '1.4.0',
          'buildNumber': 140,
          'apkUrl': 'https://dl.example.com/pos.apk',
          'changelog': 'hello',
        }),
      );
      final manifest =
          await service.fetchManifest('https://dl.example.com/m.json');
      expect(manifest.versionName, '1.4.0');
      expect(manifest.buildNumber, 140);
      expect(manifest.changelog, 'hello');
    });

    test('throws when URL is empty', () async {
      final service = _serviceReturning(status: 200, body: '{}');
      await expectLater(
        service.fetchManifest(''),
        throwsA(isA<UpdateServiceException>()),
      );
    });

    test('throws when URL is syntactically invalid', () async {
      final service = _serviceReturning(status: 200, body: '{}');
      await expectLater(
        service.fetchManifest('not-a-url'),
        throwsA(isA<UpdateServiceException>()),
      );
    });

    test('throws UpdateServiceException on non-200', () async {
      final service = _serviceReturning(status: 404, body: 'Not Found');
      await expectLater(
        service.fetchManifest('https://dl.example.com/m.json'),
        throwsA(isA<UpdateServiceException>()),
      );
    });

    test('throws UpdateServiceException on non-JSON body', () async {
      final service =
          _serviceReturning(status: 200, body: '<html>oops</html>');
      await expectLater(
        service.fetchManifest('https://dl.example.com/m.json'),
        throwsA(isA<UpdateServiceException>()),
      );
    });

    test('throws UpdateServiceException when required fields are missing',
        () async {
      final service = _serviceReturning(
        status: 200,
        body: jsonEncode({'versionName': '1.0.0'}), // no buildNumber / apkUrl
      );
      await expectLater(
        service.fetchManifest('https://dl.example.com/m.json'),
        throwsA(isA<UpdateServiceException>()),
      );
    });
  });
}
