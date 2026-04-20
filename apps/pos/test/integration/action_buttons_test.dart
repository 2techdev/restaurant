/// Integration test for action buttons (SambaPOS-style function buttons).
///
/// Exercises the repository seed + CRUD paths end-to-end against a real
/// in-memory Drift database so we catch migration / serialization drift
/// (action_payload JSON, position + actionType enums stored as text).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/action_buttons/data/repositories/action_button_repository.dart';
import 'package:gastrocore_pos/features/action_buttons/domain/entities/action_button_entity.dart';

const _tenantId = 'pilot-tenant';

void main() {
  group('ActionButtonRepository', () {
    late AppDatabase db;
    late ActionButtonRepository repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = ActionButtonRepository(db);
    });

    tearDown(() => db.close());

    test('seedDefaults installs the five standard buttons', () async {
      await repo.seedDefaults(_tenantId);
      final all = await repo.getAll(_tenantId);

      expect(all, hasLength(5));

      final types = all.map((b) => b.actionType).toSet();
      expect(types, containsAll(<ActionButtonType>{
        ActionButtonType.percentDiscount,
        ActionButtonType.markGift,
        ActionButtonType.addNote,
        ActionButtonType.printBill,
        ActionButtonType.setCourse,
      }));

      final percent = all.firstWhere(
        (b) => b.actionType == ActionButtonType.percentDiscount,
      );
      expect(percent.actionPayload['percent'], 10,
          reason: 'Default percent-discount button should carry %10 payload');
      expect(percent.position, ActionButtonPosition.ticketScreen);
      expect(percent.isActive, isTrue);

      final gang = all.firstWhere(
        (b) => b.actionType == ActionButtonType.setCourse,
      );
      expect(gang.actionPayload['gangId'], 'gang-2',
          reason: 'Default course button must target Gang 2');
    });

    test('seedDefaults is idempotent — second call inserts nothing', () async {
      await repo.seedDefaults(_tenantId);
      await repo.seedDefaults(_tenantId);
      final all = await repo.getAll(_tenantId);
      expect(all, hasLength(5),
          reason: 'Seed must not duplicate rows on a second boot');
    });

    test('percentDiscount payload round-trips through Drift JSON', () async {
      await repo.seedDefaults(_tenantId);
      final percent = (await repo.getAll(_tenantId)).firstWhere(
        (b) => b.actionType == ActionButtonType.percentDiscount,
      );

      await repo.update(percent.copyWith(
        actionPayload: <String, dynamic>{'percent': 25},
        label: '25% Rabatt',
      ));

      final reread = await repo.getById(percent.id);
      expect(reread, isNotNull);
      expect(reread!.actionPayload['percent'], 25);
      expect(reread.label, '25% Rabatt');
    });

    test('markGift entry is wired for the ticket screen with no payload',
        () async {
      await repo.seedDefaults(_tenantId);
      final gift = (await repo.getAll(_tenantId)).firstWhere(
        (b) => b.actionType == ActionButtonType.markGift,
      );

      // Gift button is a pure 100%-discount trigger — the dispatcher
      // supplies the discount value, not the payload.
      expect(gift.actionPayload, isEmpty);
      expect(gift.position, ActionButtonPosition.ticketScreen);
      expect(gift.isActive, isTrue);
    });

    test('watchByPosition excludes inactive rows', () async {
      await repo.seedDefaults(_tenantId);
      final all = await repo.getAll(_tenantId);
      final first = all.first;
      await repo.update(first.copyWith(isActive: false));

      final active = await repo
          .watchByPosition(_tenantId, ActionButtonPosition.ticketScreen)
          .first;
      expect(active.any((b) => b.id == first.id), isFalse,
          reason: 'Disabled buttons must not render on the POS shell');
    });

    test('softDelete hides rows from subsequent queries', () async {
      await repo.seedDefaults(_tenantId);
      final first = (await repo.getAll(_tenantId)).first;
      await repo.softDelete(first.id);

      final after = await repo.getAll(_tenantId);
      expect(after.any((b) => b.id == first.id), isFalse);
      expect(after, hasLength(4));
    });
  });
}
