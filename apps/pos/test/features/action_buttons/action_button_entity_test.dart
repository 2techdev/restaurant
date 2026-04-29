/// Tests for [ActionButtonEntity.isVisibleForRole].
///
/// Role gating is a Pilot v3 deliverable. The contract is:
///   * null / empty roleFilter → visible to everyone (backwards-compat
///     default, matches what production buttons looked like before the
///     column existed).
///   * non-empty roleFilter → only the named roles see the button.
///   * admin always sees every button so a misconfigured filter can't
///     lock the operator out of their own POS.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/action_buttons/domain/entities/action_button_entity.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';

ActionButtonEntity _btn({List<String>? roleFilter}) => ActionButtonEntity(
      id: 'b1',
      tenantId: 't1',
      label: 'Test',
      position: ActionButtonPosition.ticketScreen,
      actionType: ActionButtonType.addNote,
      actionPayload: const <String, dynamic>{},
      roleFilter: roleFilter,
    );

void main() {
  group('ActionButtonEntity.isVisibleForRole', () {
    test('null roleFilter is visible to every role', () {
      final b = _btn(roleFilter: null);
      for (final r in UserRole.values) {
        expect(b.isVisibleForRole(r), isTrue, reason: r.name);
      }
    });

    test('empty roleFilter is visible to every role', () {
      final b = _btn(roleFilter: const <String>[]);
      for (final r in UserRole.values) {
        expect(b.isVisibleForRole(r), isTrue, reason: r.name);
      }
    });

    test('non-empty filter gates to named roles only', () {
      final b = _btn(roleFilter: const ['manager', 'cashier']);
      expect(b.isVisibleForRole(UserRole.manager), isTrue);
      expect(b.isVisibleForRole(UserRole.cashier), isTrue);
      expect(b.isVisibleForRole(UserRole.waiter), isFalse);
      expect(b.isVisibleForRole(UserRole.kitchen), isFalse);
    });

    test('admin always sees every button regardless of filter', () {
      // A filter that explicitly excludes admin must still grant admin
      // visibility — otherwise a misconfigured filter could hide the
      // buttons an admin needs to clean up the filter itself.
      final b = _btn(roleFilter: const ['waiter']);
      expect(b.isVisibleForRole(UserRole.admin), isTrue);
    });

    test('unknown role names are ignored', () {
      // A stale seed from a future build may reference roles that no
      // longer exist. Those should simply not match — not crash.
      final b = _btn(roleFilter: const ['superuser', 'manager']);
      expect(b.isVisibleForRole(UserRole.manager), isTrue);
      expect(b.isVisibleForRole(UserRole.waiter), isFalse);
    });
  });
}
