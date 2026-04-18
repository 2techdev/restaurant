import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_boss/features/auth/auth_state.dart';
import 'package:gastrocore_models/gastrocore_models.dart';

void main() {
  group('isOwnerRole', () {
    test('admin is owner', () {
      expect(isOwnerRole(UserRole.admin), isTrue);
    });

    test('manager is owner', () {
      expect(isOwnerRole(UserRole.manager), isTrue);
    });

    test('waiter is not owner', () {
      expect(isOwnerRole(UserRole.waiter), isFalse);
    });

    test('cashier is not owner', () {
      expect(isOwnerRole(UserRole.cashier), isFalse);
    });

    test('kitchen is not owner', () {
      expect(isOwnerRole(UserRole.kitchen), isFalse);
    });
  });

  group('BossSession', () {
    final user = UserEntity(
      id: 'u1',
      tenantId: 't1',
      name: 'Owner',
      pinHash: '',
      role: UserRole.admin,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    test('isExpired returns false for future expiry', () {
      final s = BossSession(
        user: user,
        token: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(s.isExpired, isFalse);
    });

    test('isExpired returns true for past expiry', () {
      final s = BossSession(
        user: user,
        token: 'tok',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(s.isExpired, isTrue);
    });

    test('hasOwnerAccess true for admin', () {
      final s = BossSession(
        user: user,
        token: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(s.hasOwnerAccess, isTrue);
    });

    test('hasOwnerAccess false for waiter', () {
      final waiter = UserEntity(
        id: 'u2',
        tenantId: 't1',
        name: 'Waiter',
        pinHash: '',
        role: UserRole.waiter,
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final s = BossSession(
        user: waiter,
        token: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(s.hasOwnerAccess, isFalse);
    });
  });
}
