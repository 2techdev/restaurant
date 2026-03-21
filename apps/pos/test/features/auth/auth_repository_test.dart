/// Unit + integration tests for [AuthRepositoryImpl] and [CurrentUserNotifier].
///
/// Uses an in-memory Drift database — no Flutter engine required.
/// Run with:
///   flutter test test/features/auth/auth_repository_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-auth-test';

UserEntity _makeUser({
  String? id,
  String? tenantId,
  String name = 'Anna Müller',
  String pinHash = 'abc123hash',
  UserRole role = UserRole.waiter,
  bool isActive = true,
}) {
  final now = DateTime(2026, 3, 20, 10, 0);
  return UserEntity(
    id: id ?? IdGenerator.generateId(),
    tenantId: tenantId ?? _tenantId,
    name: name,
    pinHash: pinHash,
    role: role,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // AuthRepositoryImpl — CRUD
  // =========================================================================

  group('AuthRepositoryImpl — CRUD', () {
    late AppDatabase db;
    late AuthRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = AuthRepositoryImpl(db);
    });

    tearDown(() async => db.close());

    test('createUser persists a user', () async {
      final user = _makeUser();
      await repo.createUser(user);

      final all = await repo.getAllUsers(_tenantId);
      expect(all.length, equals(1));
      expect(all.first.id, equals(user.id));
      expect(all.first.name, equals('Anna Müller'));
    });

    test('getAllUsers returns only non-deleted users for tenant', () async {
      final u1 = _makeUser(name: 'Alice');
      final u2 = _makeUser(name: 'Bob');
      await repo.createUser(u1);
      await repo.createUser(u2);

      // Soft-delete u2
      await repo.deleteUser(u2.id);

      final all = await repo.getAllUsers(_tenantId);
      expect(all.length, equals(1));
      expect(all.first.name, equals('Alice'));
    });

    test('getAllUsers excludes users from other tenants', () async {
      final mine = _makeUser(tenantId: _tenantId, name: 'Mine');
      final other = _makeUser(tenantId: 'other-tenant', name: 'Other');
      await repo.createUser(mine);
      await repo.createUser(other);

      final result = await repo.getAllUsers(_tenantId);
      expect(result.length, equals(1));
      expect(result.first.name, equals('Mine'));
    });

    test('getUserByPin returns matching active user', () async {
      final user = _makeUser(pinHash: 'pin-hash-1234');
      await repo.createUser(user);

      final found = await repo.getUserByPin(_tenantId, 'pin-hash-1234');
      expect(found, isNotNull);
      expect(found!.id, equals(user.id));
    });

    test('getUserByPin returns null for wrong pin', () async {
      final user = _makeUser(pinHash: 'correct-hash');
      await repo.createUser(user);

      final found = await repo.getUserByPin(_tenantId, 'wrong-hash');
      expect(found, isNull);
    });

    test('getUserByPin returns null for inactive user', () async {
      final user = _makeUser(pinHash: 'hash-inactive', isActive: false);
      await repo.createUser(user);

      final found = await repo.getUserByPin(_tenantId, 'hash-inactive');
      expect(found, isNull);
    });

    test('getUserByPin returns null for deleted user', () async {
      final user = _makeUser(pinHash: 'hash-deleted');
      await repo.createUser(user);
      await repo.deleteUser(user.id);

      final found = await repo.getUserByPin(_tenantId, 'hash-deleted');
      expect(found, isNull);
    });

    test('updateUser persists name, role, and isActive changes', () async {
      final user = _makeUser(name: 'Before', role: UserRole.waiter);
      await repo.createUser(user);

      final updated = user.copyWith(
        name: 'After',
        role: UserRole.manager,
        isActive: false,
      );
      await repo.updateUser(updated);

      final all = await repo.getAllUsers(_tenantId);
      // isActive: false means the user is inactive but not deleted
      // getAllUsers filters by isDeleted, not isActive
      expect(all.first.name, equals('After'));
      expect(all.first.role, equals(UserRole.manager));
      expect(all.first.isActive, isFalse);
    });

    test('deleteUser soft-deletes — user no longer appears in getAllUsers', () async {
      final user = _makeUser();
      await repo.createUser(user);
      await repo.deleteUser(user.id);

      final all = await repo.getAllUsers(_tenantId);
      expect(all, isEmpty);
    });

    test('deleteUser with nonexistent id is a no-op', () async {
      await expectLater(repo.deleteUser('nonexistent-id'), completes);
    });
  });

  // =========================================================================
  // AuthRepositoryImpl — role checks
  // =========================================================================

  group('AuthRepositoryImpl — role checks', () {
    late AppDatabase db;
    late AuthRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = AuthRepositoryImpl(db);
    });

    tearDown(() async => db.close());

    test('all UserRole values can be stored and retrieved', () async {
      for (final role in UserRole.values) {
        final user = _makeUser(
          id: IdGenerator.generateId(),
          name: role.name,
          role: role,
        );
        await repo.createUser(user);
      }

      final all = await repo.getAllUsers(_tenantId);
      final roles = all.map((u) => u.role).toSet();
      expect(roles, containsAll(UserRole.values));
    });

    test('admin user can be looked up by pin', () async {
      final admin = _makeUser(role: UserRole.admin, pinHash: 'admin-pin');
      await repo.createUser(admin);

      final found = await repo.getUserByPin(_tenantId, 'admin-pin');
      expect(found!.role, equals(UserRole.admin));
    });

    test('manager user can be looked up by pin', () async {
      final mgr = _makeUser(role: UserRole.manager, pinHash: 'mgr-pin');
      await repo.createUser(mgr);

      final found = await repo.getUserByPin(_tenantId, 'mgr-pin');
      expect(found!.role, equals(UserRole.manager));
    });
  });

  // =========================================================================
  // UserEntity — equality & copyWith
  // =========================================================================

  group('UserEntity', () {
    final dt = DateTime(2026, 1, 1);

    UserEntity base() => UserEntity(
          id: 'user-1',
          tenantId: 'tenant-1',
          name: 'Test User',
          pinHash: 'hash',
          role: UserRole.cashier,
          isActive: true,
          createdAt: dt,
          updatedAt: dt,
        );

    test('equality is value-based', () {
      expect(base(), equals(base()));
    });

    test('different id → not equal', () {
      final a = base();
      final b = a.copyWith(id: 'user-2');
      expect(a, isNot(equals(b)));
    });

    test('copyWith overrides only specified fields', () {
      final original = base();
      final copy = original.copyWith(name: 'New Name', role: UserRole.kitchen);
      expect(copy.name, 'New Name');
      expect(copy.role, UserRole.kitchen);
      expect(copy.id, original.id);
      expect(copy.pinHash, original.pinHash);
    });

    test('toString contains id and name', () {
      final s = base().toString();
      expect(s, contains('user-1'));
      expect(s, contains('Test User'));
    });
  });

  // =========================================================================
  // CurrentUserNotifier — login / logout
  // =========================================================================

  group('CurrentUserNotifier', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.createInMemory();
    });

    tearDown(() async => db.close());

    ProviderContainer makeContainer() {
      return ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          tenantIdProvider.overrideWithValue(_tenantId),
        ],
      );
    }

    test('initial state is null (no user logged in)', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      expect(container.read(currentUserProvider), isNull);
    });

    test('loginWithPin returns true and sets user on success', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final repo = container.read(authRepositoryProvider);
      final user = _makeUser(pinHash: 'good-pin');
      await repo.createUser(user);

      final result =
          await container.read(currentUserProvider.notifier).loginWithPin('good-pin');
      expect(result, isTrue);
      expect(container.read(currentUserProvider), isNotNull);
      expect(container.read(currentUserProvider)!.id, equals(user.id));
    });

    test('loginWithPin returns false for wrong pin', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final result =
          await container.read(currentUserProvider.notifier).loginWithPin('bad-pin');
      expect(result, isFalse);
      expect(container.read(currentUserProvider), isNull);
    });

    test('setUser directly sets the logged-in user', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final user = _makeUser();
      container.read(currentUserProvider.notifier).setUser(user);
      expect(container.read(currentUserProvider), equals(user));
    });

    test('logout clears the current user', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final user = _makeUser();
      container.read(currentUserProvider.notifier).setUser(user);
      container.read(currentUserProvider.notifier).logout();
      expect(container.read(currentUserProvider), isNull);
    });

    test('login then logout → null state', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final repo = container.read(authRepositoryProvider);
      final user = _makeUser(pinHash: 'pin-cycle');
      await repo.createUser(user);

      await container.read(currentUserProvider.notifier).loginWithPin('pin-cycle');
      expect(container.read(currentUserProvider), isNotNull);

      container.read(currentUserProvider.notifier).logout();
      expect(container.read(currentUserProvider), isNull);
    });
  });
}
