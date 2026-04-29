/// Concurrency + correctness tests for [ReceiptCounterDao].
///
/// Swiss fiscal receipts cannot share a sequence number for the same
/// tenant. This test suite asserts:
///   * sequential calls return 1, 2, 3, … as expected,
///   * two tenants have independent counters,
///   * 50 concurrent callers for the same tenant all receive UNIQUE
///     numbers (the transaction serialises them correctly).
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/payments/data/daos/receipt_counter_dao.dart';

void main() {
  group('ReceiptCounterDao', () {
    late AppDatabase db;
    late ReceiptCounterDao dao;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      dao = db.receiptCounterDao;
    });

    tearDown(() async {
      await db.close();
    });

    test('first call for a fresh tenant returns 1', () async {
      final n = await dao.nextReceiptNumber('tenant-a');
      expect(n, 1);
    });

    test('peekCurrent starts at 0 for a tenant that has not issued yet',
        () async {
      expect(await dao.peekCurrent('never-issued'), 0);
    });

    test('sequential calls return 1, 2, 3 …', () async {
      final values = <int>[];
      for (var i = 0; i < 5; i++) {
        values.add(await dao.nextReceiptNumber('tenant-a'));
      }
      expect(values, [1, 2, 3, 4, 5]);
      expect(await dao.peekCurrent('tenant-a'), 5);
    });

    test('two tenants have independent counters', () async {
      expect(await dao.nextReceiptNumber('tenant-a'), 1);
      expect(await dao.nextReceiptNumber('tenant-b'), 1);
      expect(await dao.nextReceiptNumber('tenant-a'), 2);
      expect(await dao.nextReceiptNumber('tenant-b'), 2);
      expect(await dao.peekCurrent('tenant-a'), 2);
      expect(await dao.peekCurrent('tenant-b'), 2);
    });

    test('50 concurrent callers all receive UNIQUE numbers', () async {
      const concurrent = 50;
      final futures = <Future<int>>[
        for (var i = 0; i < concurrent; i++)
          dao.nextReceiptNumber('tenant-race')
      ];
      final results = await Future.wait(futures);

      expect(results.length, concurrent);
      expect(results.toSet().length, concurrent,
          reason: 'every issued number must be unique');
      // All values fall within the expected range.
      expect(results.every((v) => v >= 1 && v <= concurrent), isTrue);
      // Counter ends at exactly `concurrent`.
      expect(await dao.peekCurrent('tenant-race'), concurrent);
    });
  });
}
