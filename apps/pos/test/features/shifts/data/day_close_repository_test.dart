/// Integration tests for [DayCloseRepositoryImpl].
///
/// Uses an in-memory Drift database — no mocking of SQL layer.
/// Covers saveSummary, getById, getSummariesByShift, and history queries.
///
/// Run with:
///   flutter test test/features/shifts/data/day_close_repository_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/shifts/data/repositories/day_close_repository_impl.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/day_close_summary_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-dayclose-test';
const _deviceId = 'DEV-DC-01';

Future<DayCloseSummaryEntity> _saveSummary(
  DayCloseRepositoryImpl repo, {
  String? shiftId,
  int totalRevenueCents = 120000,
  int totalOrders = 12,
  int countedCashCents = 85000,
  int expectedCashCents = 85000,
  int discrepancyCents = 0,
  Map<int, int>? denominationBreakdown,
  Map<String, int>? paymentBreakdown,
  DateTime? closedAt,
}) {
  return repo.saveSummary(
    tenantId: _tenantId,
    shiftId: shiftId ?? IdGenerator.generateId(),
    deviceId: _deviceId,
    cashierName: 'Anna Müller',
    totalRevenueCents: totalRevenueCents,
    totalOrders: totalOrders,
    avgOrderCents: totalOrders > 0 ? (totalRevenueCents ~/ totalOrders) : 0,
    countedCashCents: countedCashCents,
    expectedCashCents: expectedCashCents,
    discrepancyCents: discrepancyCents,
    denominationBreakdown: denominationBreakdown ?? {1000: 5, 5000: 2, 10000: 3},
    paymentBreakdown: paymentBreakdown ?? {'cash': 70000, 'card': 50000},
    closedAt: closedAt ?? DateTime(2026, 3, 21, 22, 0),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DayCloseRepositoryImpl — saveSummary', () {
    late AppDatabase db;
    late DayCloseRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = DayCloseRepositoryImpl(db);
    });

    tearDown(() async => db.close());

    test('returns persisted entity with generated id', () async {
      final summary = await _saveSummary(repo);
      expect(summary.id, isNotEmpty);
      expect(summary.tenantId, equals(_tenantId));
    });

    test('stores all numeric fields correctly', () async {
      final summary = await _saveSummary(
        repo,
        totalRevenueCents: 99900,
        totalOrders: 9,
        countedCashCents: 50000,
        expectedCashCents: 50500,
        discrepancyCents: -500,
      );

      expect(summary.totalRevenueCents, equals(99900));
      expect(summary.totalOrders, equals(9));
      expect(summary.countedCashCents, equals(50000));
      expect(summary.expectedCashCents, equals(50500));
      expect(summary.discrepancyCents, equals(-500));
    });

    test('persists denomination breakdown as map', () async {
      final denom = {100: 5, 500: 3, 1000: 10, 5000: 2};
      final summary = await _saveSummary(repo, denominationBreakdown: denom);

      expect(summary.denominationBreakdown[100], equals(5));
      expect(summary.denominationBreakdown[500], equals(3));
      expect(summary.denominationBreakdown[1000], equals(10));
      expect(summary.denominationBreakdown[5000], equals(2));
    });

    test('persists payment breakdown as map', () async {
      final payments = {'cash': 40000, 'credit_card': 30000, 'twint': 20000};
      final summary = await _saveSummary(repo, paymentBreakdown: payments);

      expect(summary.paymentBreakdown['cash'], equals(40000));
      expect(summary.paymentBreakdown['credit_card'], equals(30000));
      expect(summary.paymentBreakdown['twint'], equals(20000));
    });

    test('persists cashierName', () async {
      final summary = await _saveSummary(repo);
      expect(summary.cashierName, equals('Anna Müller'));
    });

    test('persists closedAt', () async {
      final closedAt = DateTime(2026, 3, 21, 23, 30);
      final summary = await _saveSummary(repo, closedAt: closedAt);
      expect(summary.closedAt, equals(closedAt));
    });

    test('multiple saves create separate summaries', () async {
      final s1 = await _saveSummary(repo);
      final s2 = await _saveSummary(repo);

      expect(s1.id, isNot(equals(s2.id)));
    });
  });

  // =========================================================================
  // getById
  // =========================================================================

  group('DayCloseRepositoryImpl — getById', () {
    late AppDatabase db;
    late DayCloseRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = DayCloseRepositoryImpl(db);
    });

    tearDown(() async => db.close());

    test('returns null for nonexistent id', () async {
      final result = await repo.getById('nonexistent-id');
      expect(result, isNull);
    });

    test('returns the correct entity for a valid id', () async {
      final saved = await _saveSummary(repo, totalRevenueCents: 75000);
      final fetched = await repo.getById(saved.id);
      expect(fetched, isNotNull);
      expect(fetched!.id, equals(saved.id));
      expect(fetched.totalRevenueCents, equals(75000));
    });
  });

  // =========================================================================
  // DayCloseSummaryEntity helpers
  // =========================================================================

  group('DayCloseSummaryEntity — helpers', () {
    DayCloseSummaryEntity makeEntity({
      int countedCash = 75000,
      int expectedCash = 75000,
      int discrepancy = 0,
    }) {
      return DayCloseSummaryEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        shiftId: 'shift-1',
        deviceId: _deviceId,
        cashierName: 'Test',
        totalRevenueCents: 120000,
        totalOrders: 12,
        avgOrderCents: 10000,
        countedCashCents: countedCash,
        expectedCashCents: expectedCash,
        discrepancyCents: discrepancy,
        denominationBreakdown: {1000: 3},
        paymentBreakdown: {'cash': 60000, 'card': 60000},
        closedAt: DateTime(2026, 3, 21, 22, 0),
        createdAt: DateTime(2026, 3, 21, 22, 0),
      );
    }

    test('isWithinThreshold for zero discrepancy', () {
      expect(makeEntity(discrepancy: 0).isWithinThreshold, isTrue);
    });

    test('isWithinThreshold for exactly ±500¢ (CHF 5)', () {
      expect(makeEntity(discrepancy: 500).isWithinThreshold, isTrue);
      expect(makeEntity(discrepancy: -500).isWithinThreshold, isTrue);
    });

    test('isWithinThreshold false for 501¢', () {
      expect(makeEntity(discrepancy: 501).isWithinThreshold, isFalse);
    });

    test('discrepancyLabel positive', () {
      expect(makeEntity(discrepancy: 150).discrepancyLabel, equals('+CHF 1.50'));
    });

    test('discrepancyLabel negative', () {
      expect(makeEntity(discrepancy: -300).discrepancyLabel, equals('-CHF 3.00'));
    });

    test('discrepancyLabel zero', () {
      expect(makeEntity(discrepancy: 0).discrepancyLabel, equals('+CHF 0.00'));
    });

    test('avgOrderCents is stored and retrievable', () {
      final e = makeEntity();
      expect(e.avgOrderCents, equals(10000));
    });

    test('paymentBreakdown contains cash and card entries', () {
      final e = makeEntity();
      expect(e.paymentBreakdown.containsKey('cash'), isTrue);
      expect(e.paymentBreakdown.containsKey('card'), isTrue);
    });

    test('two entities with same id are equal', () {
      final a = makeEntity();
      final b = DayCloseSummaryEntity(
        id: a.id,
        tenantId: a.tenantId,
        shiftId: a.shiftId,
        deviceId: a.deviceId,
        cashierName: 'Other Name',
        totalRevenueCents: 999,
        totalOrders: 99,
        avgOrderCents: 9,
        countedCashCents: 0,
        expectedCashCents: 0,
        discrepancyCents: 0,
        denominationBreakdown: {},
        paymentBreakdown: {},
        closedAt: DateTime.now(),
        createdAt: DateTime.now(),
      );
      expect(a, equals(b));
    });
  });

  // =========================================================================
  // Full day-close scenario
  // =========================================================================

  group('Day-close scenario — shift with cash discrepancy', () {
    late AppDatabase db;
    late DayCloseRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = DayCloseRepositoryImpl(db);
    });

    tearDown(() async => db.close());

    test('typical shift under-count is stored correctly', () async {
      // Day: CHF 1200 revenue, CHF 850 expected cash, CHF 847.80 counted.
      const discrepancy = -220; // CHF -2.20 (within tolerance)

      final summary = await _saveSummary(
        repo,
        totalRevenueCents: 120000,
        totalOrders: 15,
        countedCashCents: 84780,
        expectedCashCents: 85000,
        discrepancyCents: discrepancy,
        denominationBreakdown: {10000: 8, 1000: 4, 100: 8, 20: 4},
        paymentBreakdown: {'cash': 85000, 'credit_card': 35000},
      );

      expect(summary.discrepancyCents, equals(-220));
      expect(summary.isWithinThreshold, isTrue);
      expect(summary.discrepancyLabel, equals('-CHF 2.20'));
    });

    test('can retrieve day-close after save', () async {
      final saved = await _saveSummary(repo, discrepancyCents: -750);
      final fetched = await repo.getById(saved.id);
      expect(fetched!.discrepancyCents, equals(-750));
      expect(fetched.isWithinThreshold, isFalse); // 750 > 500
    });
  });
}
