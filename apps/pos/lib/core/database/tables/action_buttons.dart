/// User-defined function buttons (SambaPOS-style "Automation Commands").
///
/// Operators configure a label, colour, target surface and action type +
/// payload; when tapped the dispatcher invokes the appropriate notifier.
/// `actionType` is stored as a string so new action kinds do not force a
/// migration — unknown types degrade to a disabled tile rather than crash.
library;

import 'package:drift/drift.dart';

@DataClassName('ActionButton')
class ActionButtons extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();

  /// Rendered label (uppercased at render time).
  TextColumn get label => text()();

  /// Optional ARGB colour override. NULL uses a semantic default based
  /// on [actionType] (discount = orange, gift = red, etc.).
  IntColumn get colorValue => integer().nullable()();

  /// Optional Material icon identifier (e.g. 'percent', 'card_giftcard').
  /// Resolved through a hand-maintained allow-list in the dispatcher.
  TextColumn get iconName => text().nullable()();

  /// Surface on which this button renders. See [ActionButtonPosition].
  TextColumn get position => text()();

  /// Machine name of the action this button performs. See [ActionButtonType].
  TextColumn get actionType => text()();

  /// JSON-encoded payload, interpreted by the dispatcher per actionType.
  /// Examples:
  ///   percentDiscount  -> {"percent": 10}
  ///   fixedDiscount    -> {"amount": 500, "currency": "CHF"}  (cents)
  ///   setCourse        -> {"gangId": "gang-2"}
  TextColumn get actionPayload => text().withDefault(const Constant('{}'))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Reserved for a later role gate (JSON array of role names). Unused in v1.
  TextColumn get roleFilter => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
