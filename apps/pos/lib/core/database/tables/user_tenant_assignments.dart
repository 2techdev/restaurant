import 'package:drift/drift.dart';

/// N:M assignments mapping a user (operator) to one or more tenants.
///
/// The `users` table still carries a primary `tenantId` (the user's home
/// tenant — the one created at first onboarding). This table layers
/// additional tenants on top so an operator can clock into any restaurant
/// they have been granted access to.
///
/// Pilot devices remain single-tenant: the runtime tenant switcher is gated
/// behind the `multiTenantSwitcherEnabled` flag in [AppSettings] (default
/// false), so the schema migration runs but the UI hides the picker until
/// an admin enables it. Server-side tenant assignments are mirrored via
/// the cloud-sync pull on first login per user.
///
/// Schema introduced 2026-05-09 (schema v23).
@DataClassName('UserTenantAssignment')
class UserTenantAssignments extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get tenantId => text()();

  /// Optional human role override per tenant. If null, the user's primary
  /// role (from `users.role`) applies. Lets a manager at tenant A be a
  /// waiter at tenant B without duplicating user rows.
  TextColumn get roleOverride => text().nullable()();

  /// Server-side ack: false until the cloud confirms the assignment is
  /// live. Local UI surfaces unconfirmed assignments greyed out.
  BoolColumn get isConfirmed => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  // Soft-delete pair so revocations sync back through the standard pipeline.
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
