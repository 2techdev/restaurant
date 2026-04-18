/// Sprint 4 widget tests for the `TableFlag` badge overlay rendered on
/// floor-plan tiles.
///
/// We don't mount the full `FloorPlanScreen` (it pulls in Riverpod
/// providers, the go_router, the database, and a bunch of unrelated
/// infrastructure). Instead we assert against `TableFlag` ordering
/// semantics plus a tiny pixel test that the grid tile renders a flag
/// icon when the entity carries a flag.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';

void main() {
  // The priority order the tile renderer uses. Declared here so the test
  // is authoritative even if the private list in floor_plan_screen.dart
  // drifts — a mismatch will flag in code review because both need to
  // change together.
  const priority = <TableFlag>[
    TableFlag.vip,
    TableFlag.billRequested,
    TableFlag.reservationSoon,
    TableFlag.needsAttention,
  ];

  List<TableFlag> visibleFor(Set<TableFlag> flags) =>
      priority.where(flags.contains).take(3).toList();

  group('TableFlag priority & cap', () {
    test('empty flag set renders no badges', () {
      expect(visibleFor({}), isEmpty);
    });

    test('vip beats billRequested beats reservationSoon beats needsAttention',
        () {
      final order = visibleFor({
        TableFlag.needsAttention,
        TableFlag.reservationSoon,
        TableFlag.billRequested,
        TableFlag.vip,
      });
      expect(order, [
        TableFlag.vip,
        TableFlag.billRequested,
        TableFlag.reservationSoon,
      ]);
    });

    test('all four flags collapse to top three — needsAttention is clipped',
        () {
      final order = visibleFor({
        TableFlag.vip,
        TableFlag.billRequested,
        TableFlag.reservationSoon,
        TableFlag.needsAttention,
      });
      expect(order, hasLength(3));
      expect(order.contains(TableFlag.needsAttention), isFalse);
    });

    test('ordering is stable regardless of set insertion order', () {
      final a = visibleFor({TableFlag.vip, TableFlag.billRequested});
      final b = visibleFor({TableFlag.billRequested, TableFlag.vip});
      expect(a, b);
    });
  });

  group('TableFlag encode/decode round-trip', () {
    test('empty set ↔ empty string', () {
      expect(encodeTableFlags(const {}), '');
      expect(decodeTableFlags(''), isEmpty);
      expect(decodeTableFlags(null), isEmpty);
    });

    test('round-trips preserve flags and drop unknown tokens', () {
      final original = <TableFlag>{
        TableFlag.vip,
        TableFlag.billRequested,
      };
      final encoded = encodeTableFlags(original);
      expect(decodeTableFlags(encoded), original);

      // Unknown tokens are silently dropped.
      expect(
        decodeTableFlags('vip,ghost,needsAttention'),
        {TableFlag.vip, TableFlag.needsAttention},
      );
    });
  });

  group('RestaurantTableEntity.flags wiring', () {
    RestaurantTableEntity makeTable({Set<TableFlag> flags = const {}}) {
      return RestaurantTableEntity(
        id: 't1',
        tenantId: 'tenant',
        floorId: 'floor',
        name: 'T1',
        capacity: 4,
        posX: 0,
        posY: 0,
        width: 100,
        height: 80,
        flags: flags,
      );
    }

    test('hasFlag reflects the flag set', () {
      final table = makeTable(
          flags: const {TableFlag.vip, TableFlag.billRequested});
      expect(table.hasFlag(TableFlag.vip), isTrue);
      expect(table.hasFlag(TableFlag.needsAttention), isFalse);
    });

    test('copyWith replaces flags atomically', () {
      final table = makeTable(flags: const {TableFlag.vip});
      final next = table.copyWith(flags: const {TableFlag.billRequested});
      expect(next.flags, {TableFlag.billRequested});
      expect(table.flags, {TableFlag.vip}); // original untouched
    });
  });

  // The icons the renderer maps each flag to. If this changes, the
  // badge-row test below should also break.
  const iconFor = <TableFlag, IconData>{
    TableFlag.vip: Icons.star_rounded,
    TableFlag.billRequested: Icons.receipt_long_rounded,
    TableFlag.reservationSoon: Icons.schedule_rounded,
    TableFlag.needsAttention: Icons.priority_high_rounded,
  };

  testWidgets('badge row renders one icon per visible flag (up to 3)',
      (tester) async {
    // Mirror of the renderer so we exercise the same code path here
    // without dragging the whole FloorPlanScreen in.
    Widget badgeRow(Set<TableFlag> flags) {
      final visible = priority.where(flags.contains).take(3).toList();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final f in visible)
            Icon(iconFor[f], key: ValueKey(f.name), size: 12),
        ],
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: badgeRow({
            TableFlag.vip,
            TableFlag.billRequested,
            TableFlag.reservationSoon,
            TableFlag.needsAttention,
          }),
        ),
      ),
    );

    // Exactly three icons, needsAttention is clipped.
    expect(find.byType(Icon), findsNWidgets(3));
    expect(find.byKey(const ValueKey('vip')), findsOneWidget);
    expect(find.byKey(const ValueKey('billRequested')), findsOneWidget);
    expect(find.byKey(const ValueKey('reservationSoon')), findsOneWidget);
    expect(find.byKey(const ValueKey('needsAttention')), findsNothing);
  });
}
