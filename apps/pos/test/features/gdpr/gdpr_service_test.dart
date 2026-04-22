/// Tests for the GDPR export + anonymisation service.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/gdpr/data/gdpr_service.dart';

const _tenant = 't-gdpr';

Future<String> _seedCustomer(
  AppDatabase db, {
  required String id,
  required String name,
  String? phone,
  String? email,
  String? address,
  String? notes,
  String? birthday,
}) async {
  final now = DateTime.now();
  await db.into(db.customers).insert(CustomersCompanion.insert(
        id: id,
        tenantId: _tenant,
        name: name,
        phone: Value(phone),
        email: Value(email),
        address: Value(address),
        notes: Value(notes),
        birthday: Value(birthday),
        createdAt: now,
        updatedAt: now,
      ));
  return id;
}

Future<void> _seedAddress(
  AppDatabase db, {
  required String id,
  required String customerId,
  required String street,
}) async {
  await db.into(db.customerAddresses).insert(CustomerAddressesCompanion.insert(
        id: id,
        customerId: customerId,
        street: street,
        city: 'Zürich',
        postalCode: '8001',
        createdAt: DateTime.now(),
      ));
}

Future<void> _seedTicket(
  AppDatabase db, {
  required String id,
  required String customerId,
  required String customerName,
}) async {
  final now = DateTime.now();
  await db.into(db.tickets).insert(TicketsCompanion.insert(
        id: id,
        tenantId: _tenant,
        orderNumber: 1,
        customerId: Value(customerId),
        customerName: Value(customerName),
        openedAt: now,
        createdAt: now,
        updatedAt: now,
        deviceId: 'DEV-1',
      ));
}

Future<void> _seedReservation(
  AppDatabase db, {
  required String id,
  required String customerName,
  String? customerPhone,
}) async {
  final now = DateTime.now();
  await db.into(db.reservations).insert(ReservationsCompanion.insert(
        id: id,
        tenantId: _tenant,
        customerName: customerName,
        customerPhone: Value(customerPhone),
        date: now,
        timeStart: now,
        timeEnd: now.add(const Duration(hours: 2)),
        createdAt: now,
        updatedAt: now,
      ));
}

void main() {
  group('GdprService.exportForCustomer', () {
    late AppDatabase db;
    late GdprService service;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      service = GdprService(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('returns null for a non-existent customer id', () async {
      expect(await service.exportForCustomer('does-not-exist'), isNull);
    });

    test('bundles the customer row, addresses, tickets, reservations',
        () async {
      await _seedCustomer(db,
          id: 'c1',
          name: 'Hans Muster',
          phone: '+41 79 111 22 33',
          email: 'hans@example.ch',
          birthday: '1975-05-12');
      await _seedAddress(db,
          id: 'a1', customerId: 'c1', street: 'Bahnhofstrasse 1');
      await _seedAddress(db,
          id: 'a2', customerId: 'c1', street: 'Seefeldstrasse 22');
      await _seedTicket(db,
          id: 't1', customerId: 'c1', customerName: 'Hans Muster');
      await _seedReservation(db,
          id: 'r1',
          customerName: 'Hans Muster',
          customerPhone: '+41 79 111 22 33');
      await _seedReservation(db,
          id: 'r2',
          customerName: 'Hans Muster',
          customerPhone: '+41 79 999 99 99'); // different phone — should not match

      final bundle = await service.exportForCustomer('c1');
      expect(bundle, isNotNull);
      expect(bundle!['schema'], 'gdpr.export.v1');
      expect(bundle['customer']['name'], 'Hans Muster');
      expect(bundle['customer']['email'], 'hans@example.ch');
      expect((bundle['addresses'] as List).length, 2);
      expect((bundle['tickets'] as List).length, 1);
      // Only r1 matches (same phone); r2 has a different phone.
      expect((bundle['reservations'] as List).length, 1);
      expect((bundle['reservations'] as List).first['id'], 'r1');
    });

    test('reservations fall back to name-only match when customer has no phone',
        () async {
      await _seedCustomer(db, id: 'c2', name: 'Phoneless Pierre');
      await _seedReservation(db, id: 'r1', customerName: 'Phoneless Pierre');

      final bundle = await service.exportForCustomer('c2');
      expect((bundle!['reservations'] as List).length, 1);
    });
  });

  group('GdprService.anonymizeCustomer', () {
    late AppDatabase db;
    late GdprService service;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      service = GdprService(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('returns a not-found result when the customer does not exist',
        () async {
      final result = await service.anonymizeCustomer('ghost');
      expect(result.customerFound, isFalse);
      expect(result.totalRowsAffected, 0);
    });

    test('wipes PII, soft-deletes addresses, clears ticket customerName',
        () async {
      await _seedCustomer(db,
          id: 'cust-abcdef12',
          name: 'Marie Dubois',
          phone: '+41 78 000 00 00',
          email: 'marie@example.ch',
          address: 'Rue du Rhone 10',
          notes: 'Likes oat milk',
          birthday: '1990-01-01');
      await _seedAddress(db,
          id: 'a1', customerId: 'cust-abcdef12', street: 'A');
      await _seedAddress(db,
          id: 'a2', customerId: 'cust-abcdef12', street: 'B');
      await _seedTicket(db,
          id: 't1',
          customerId: 'cust-abcdef12',
          customerName: 'Marie Dubois');
      await _seedReservation(db,
          id: 'r1',
          customerName: 'Marie Dubois',
          customerPhone: '+41 78 000 00 00');

      final result = await service.anonymizeCustomer('cust-abcdef12');
      expect(result.customerFound, isTrue);
      expect(result.addressesRemoved, 2);
      expect(result.ticketsCleared, 1);
      expect(result.reservationsCleared, 1);

      // Customer row: PII cleared, name rewritten to a stable token.
      final scrubbed = await (db.select(db.customers)
            ..where((t) => t.id.equals('cust-abcdef12')))
          .getSingle();
      expect(scrubbed.name, 'anonymized-abcdef12');
      expect(scrubbed.phone, isNull);
      expect(scrubbed.email, isNull);
      expect(scrubbed.address, isNull);
      expect(scrubbed.notes, isNull);
      expect(scrubbed.birthday, isNull);

      // Addresses: gone.
      final addrs = await db.select(db.customerAddresses).get();
      expect(addrs, isEmpty);

      // Tickets: customerId preserved for fiscal trail, customerName null.
      final tkts = await db.select(db.tickets).get();
      expect(tkts.single.customerId, 'cust-abcdef12');
      expect(tkts.single.customerName, isNull);

      // Reservations: customer fields rewritten to the token.
      final res = await db.select(db.reservations).get();
      expect(res.single.customerName, 'anonymized-abcdef12');
      expect(res.single.customerPhone, isNull);
      expect(res.single.customerEmail, isNull);
    });

    test('only anonymises reservations matching the customer name+phone',
        () async {
      await _seedCustomer(db,
          id: 'c1', name: 'Shared Name', phone: '+41 78 000 11 11');
      await _seedReservation(db,
          id: 'match',
          customerName: 'Shared Name',
          customerPhone: '+41 78 000 11 11');
      await _seedReservation(db,
          id: 'no-match',
          customerName: 'Shared Name',
          customerPhone: '+41 79 999 99 99');

      await service.anonymizeCustomer('c1');

      final res = await db.select(db.reservations).get();
      final matchRow = res.firstWhere((r) => r.id == 'match');
      final otherRow = res.firstWhere((r) => r.id == 'no-match');
      expect(matchRow.customerName, startsWith('anonymized-'));
      expect(otherRow.customerName, 'Shared Name'); // untouched
    });
  });
}
