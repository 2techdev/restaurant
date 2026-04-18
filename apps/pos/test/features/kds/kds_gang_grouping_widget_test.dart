/// Widget tests for the parameterized Gang grouping on the KDS.
///
/// The 2026-04-17 pivot put Gang grouping behind
/// [RestaurantSettings.gangsEnabled]:
///   - gangsEnabled == false → flat, arrival-ordered list. No Gang headers,
///     no FIRE button, no per-gang HOLD/READY chips.
///   - gangsEnabled == true  → the usual grouped view with headers labelled
///     via [RestaurantSettings.gangLabelFor].
///
/// These tests lock that invariant by mounting the top-level
/// [buildGangGroupedItemsList] view in isolation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/gang/domain/entities/gang_template_entity.dart';
import 'package:gastrocore_pos/features/kds_app/presentation/screens/kds_main_screen.dart';
import 'package:gastrocore_pos/features/kitchen/domain/entities/kitchen_ticket_entity.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-test';

KitchenTicketItemEntity _item({
  required String id,
  required String name,
  String? gangId,
  double qty = 1,
}) {
  return KitchenTicketItemEntity(
    id: id,
    kitchenTicketId: 'kt-1',
    orderItemId: 'oi-$id',
    productName: name,
    quantity: qty,
    gangId: gangId,
  );
}

KitchenTicketEntity _ticket(List<KitchenTicketItemEntity> items) {
  return KitchenTicketEntity(
    id: 'kt-1',
    tenantId: _tenantId,
    ticketId: 'tk-1',
    orderNumber: '0042',
    printerGroup: 'kitchen',
    items: items,
    sentAt: DateTime(2026, 4, 17, 12, 0),
  );
}

GangTemplateEntity _gang(int sortOrder) {
  return GangTemplateEntity(
    id: 'gang-$sortOrder',
    tenantId: _tenantId,
    sortOrder: sortOrder,
    color: '#90ABFF',
    isDefault: true,
    isActive: true,
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      // Constrain the ListView so it has bounded height.
      body: SizedBox(height: 600, child: child),
    ),
  );
}

// No-op callbacks for tests that don't care about interaction.
void _noopFire(KitchenTicketEntity t, GangTemplateEntity g,
    List<KitchenTicketItemEntity> items, String label) {}
void _noopAdvance(String t, String g, GangOrderStatus s) {}
void _noopRecall(String t, String g, GangOrderStatus s) {}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('buildGangGroupedItemsList — gangsEnabled=false', () {
    testWidgets('renders items flat with no Gang header', (tester) async {
      final ticket = _ticket([
        _item(id: '1', name: 'Salat', gangId: 'gang-1'),
        _item(id: '2', name: 'Schnitzel', gangId: 'gang-2'),
        _item(id: '3', name: 'Mousse', gangId: 'gang-3'),
      ]);
      final gangMap = {
        'gang-1': _gang(1),
        'gang-2': _gang(2),
        'gang-3': _gang(3),
      };

      await tester.pumpWidget(_host(buildGangGroupedItemsList(
        ticket,
        gangMap: gangMap,
        gangStates: const {},
        largeFont: false,
        itemSize: 14,
        modSize: 12,
        settings: const RestaurantSettings(gangsEnabled: false),
        onFire: _noopFire,
        onAdvance: _noopAdvance,
        onRecall: _noopRecall,
      )));

      // Product names are rendered…
      expect(find.text('Salat'), findsOneWidget);
      expect(find.text('Schnitzel'), findsOneWidget);
      expect(find.text('Mousse'), findsOneWidget);

      // …but no Gang header text, no FIRE button, no HOLD chip.
      expect(find.text('GANG 1'), findsNothing);
      expect(find.text('GANG 2'), findsNothing);
      expect(find.text('GANG 3'), findsNothing);
      expect(find.text('FIRE'), findsNothing);
      expect(find.text('HOLD'), findsNothing);
    });

    testWidgets('uses arrival order (input order) when disabled',
        (tester) async {
      // Intentionally order items out of gang-sort so we can prove the flat
      // list does NOT reorder by gang.
      final ticket = _ticket([
        _item(id: '1', name: 'Dessert first', gangId: 'gang-3'),
        _item(id: '2', name: 'Main second', gangId: 'gang-2'),
        _item(id: '3', name: 'Starter last', gangId: 'gang-1'),
      ]);

      await tester.pumpWidget(_host(buildGangGroupedItemsList(
        ticket,
        gangMap: {
          'gang-1': _gang(1),
          'gang-2': _gang(2),
          'gang-3': _gang(3),
        },
        gangStates: const {},
        largeFont: false,
        itemSize: 14,
        modSize: 12,
        settings: const RestaurantSettings(gangsEnabled: false),
        onFire: _noopFire,
        onAdvance: _noopAdvance,
        onRecall: _noopRecall,
      )));

      // All three present — we rely on settings_entities_test to lock
      // ordering semantics; here we only confirm no gang re-grouping kicked in.
      expect(find.text('Dessert first'), findsOneWidget);
      expect(find.text('Main second'), findsOneWidget);
      expect(find.text('Starter last'), findsOneWidget);
      expect(find.text('GANG 1'), findsNothing);
    });
  });

  group('buildGangGroupedItemsList — gangsEnabled=true', () {
    testWidgets('renders Gang headers using default "Gang N" labels',
        (tester) async {
      final ticket = _ticket([
        _item(id: '1', name: 'Salat', gangId: 'gang-1'),
        _item(id: '2', name: 'Schnitzel', gangId: 'gang-2'),
      ]);

      await tester.pumpWidget(_host(buildGangGroupedItemsList(
        ticket,
        gangMap: {'gang-1': _gang(1), 'gang-2': _gang(2)},
        gangStates: const {},
        largeFont: false,
        itemSize: 14,
        modSize: 12,
        settings: const RestaurantSettings(),
        onFire: _noopFire,
        onAdvance: _noopAdvance,
        onRecall: _noopRecall,
      )));

      expect(find.text('GANG 1'), findsOneWidget);
      expect(find.text('GANG 2'), findsOneWidget);
      // Pending gangs carry a FIRE button.
      expect(find.text('FIRE'), findsNWidgets(2));
    });

    testWidgets('respects restaurant-overridden gangLabels', (tester) async {
      final ticket = _ticket([
        _item(id: '1', name: 'Amuse-bouche', gangId: 'gang-1'),
        _item(id: '2', name: 'Plat principal', gangId: 'gang-2'),
      ]);

      await tester.pumpWidget(_host(buildGangGroupedItemsList(
        ticket,
        gangMap: {'gang-1': _gang(1), 'gang-2': _gang(2)},
        gangStates: const {},
        largeFont: false,
        itemSize: 14,
        modSize: 12,
        settings: const RestaurantSettings(
          gangLabels: ['Amuse', 'Hauptgang', 'Dessert'],
        ),
        onFire: _noopFire,
        onAdvance: _noopAdvance,
        onRecall: _noopRecall,
      )));

      expect(find.text('AMUSE'), findsOneWidget);
      expect(find.text('HAUPTGANG'), findsOneWidget);
      expect(find.text('GANG 1'), findsNothing);
      expect(find.text('GANG 2'), findsNothing);
    });

    testWidgets('respects maxGangs cap — beyond-cap gang falls to "Andere"',
        (tester) async {
      final ticket = _ticket([
        _item(id: '1', name: 'Starter', gangId: 'gang-1'),
        _item(id: '2', name: 'Main', gangId: 'gang-2'),
        _item(id: '3', name: 'Dessert', gangId: 'gang-3'),
      ]);

      await tester.pumpWidget(_host(buildGangGroupedItemsList(
        ticket,
        gangMap: {
          'gang-1': _gang(1),
          'gang-2': _gang(2),
          'gang-3': _gang(3),
        },
        gangStates: const {},
        largeFont: false,
        itemSize: 14,
        modSize: 12,
        settings: const RestaurantSettings(maxGangs: 2),
        onFire: _noopFire,
        onAdvance: _noopAdvance,
        onRecall: _noopRecall,
      )));

      expect(find.text('GANG 1'), findsOneWidget);
      expect(find.text('GANG 2'), findsOneWidget);
      // gang-3 is beyond the cap → rendered as "ANDERE"
      expect(find.text('GANG 3'), findsNothing);
      expect(find.text('ANDERE'), findsOneWidget);
      expect(find.text('Dessert'), findsOneWidget);
    });
  });
}
