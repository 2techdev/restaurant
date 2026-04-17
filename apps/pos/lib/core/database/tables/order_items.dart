import 'package:drift/drift.dart';

@DataClassName('OrderItem')
class OrderItems extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get ticketId => text()();
  TextColumn get productId => text()();
  TextColumn get productName => text()(); // denormalized snapshot
  RealColumn get quantity => real().withDefault(const Constant(1.0))();
  IntColumn get unitPrice => integer()(); // cents
  IntColumn get subtotal => integer()(); // cents
  IntColumn get taxAmount => integer().withDefault(const Constant(0))(); // cents
  IntColumn get discountAmount => integer().withDefault(const Constant(0))(); // cents
  TextColumn get status => text().withDefault(const Constant('ordered'))(); // ordered, sent, preparing, ready, served, void
  BoolColumn get sentToKitchen => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  IntColumn get course => integer().withDefault(const Constant(1))();

  /// Seat number this line is assigned to, used by split-by-seat billing.
  ///
  /// `0` (default) means "shared / unassigned"; seats are 1-indexed up to the
  /// ticket's current guest count. Waiter can edit per-item.
  IntColumn get seat => integer().withDefault(const Constant(0))();

  /// Gang (course group) assigned to this order line.
  /// References gang_templates.id. Null = no Gang assigned.
  /// Waiter can override per-item at order time.
  TextColumn get gangId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
