import 'package:drift/drift.dart';

/// Tracks the lifecycle state of each Gang within an order.
///
/// Lifecycle: PENDING → FIRED → IN_PREP → READY → SERVED
///
/// One row per (order / gang) pair. Created when the first item for a gang
/// is added to an order; updated as the kitchen works through the courses.
@DataClassName('OrderGangState')
class OrderGangStates extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();

  /// The ticket (order) this gang state belongs to.
  TextColumn get ticketId => text()();

  /// Reference to [GangTemplates.id].
  TextColumn get gangTemplateId => text()();

  /// Current lifecycle status.
  /// Values: 'pending', 'fired', 'in_prep', 'ready', 'served'
  TextColumn get status =>
      text().withDefault(const Constant('pending'))();

  /// When the waiter pressed "Fire Gang" (null until fired).
  DateTimeColumn get firedAt => dateTime().nullable()();

  /// When the kitchen marked this gang ready.
  DateTimeColumn get readyAt => dateTime().nullable()();

  /// When the waiter confirmed service.
  DateTimeColumn get servedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
