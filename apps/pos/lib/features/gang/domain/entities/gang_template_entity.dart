/// Gang (course group) domain entities.
///
/// A Gang represents a course in a multi-course meal service.
/// Swiss defaults: Gang 1 = Vorspeise, Gang 2 = Hauptgang,
/// Gang 3 = Dessert, Gang 4 = Getränke.
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// GangOrderStatus
// ---------------------------------------------------------------------------

/// Lifecycle status of a Gang within an order.
enum GangOrderStatus {
  /// Gang items are queued but not yet sent to kitchen.
  pending,

  /// Waiter pressed "Fire Gang" — items sent to kitchen.
  fired,

  /// Kitchen has started preparing items in this Gang.
  inPrep,

  /// All items in this Gang are ready.
  ready,

  /// All items in this Gang have been served.
  served,
}

extension GangOrderStatusX on GangOrderStatus {
  String get label => switch (this) {
        GangOrderStatus.pending => 'PENDING',
        GangOrderStatus.fired => 'FIRED',
        GangOrderStatus.inPrep => 'IN PREP',
        GangOrderStatus.ready => 'READY',
        GangOrderStatus.served => 'SERVED',
      };

  String get dbValue => switch (this) {
        GangOrderStatus.pending => 'pending',
        GangOrderStatus.fired => 'fired',
        GangOrderStatus.inPrep => 'in_prep',
        GangOrderStatus.ready => 'ready',
        GangOrderStatus.served => 'served',
      };

  static GangOrderStatus fromDb(String value) => switch (value) {
        'fired' => GangOrderStatus.fired,
        'in_prep' => GangOrderStatus.inPrep,
        'ready' => GangOrderStatus.ready,
        'served' => GangOrderStatus.served,
        _ => GangOrderStatus.pending,
      };
}

// ---------------------------------------------------------------------------
// GangTemplateEntity
// ---------------------------------------------------------------------------

/// Immutable representation of a Gang template (course definition).
class GangTemplateEntity {
  final String id;
  final String tenantId;
  final String name;
  final int sortOrder;

  /// Hex color string, e.g. '#528DFF'.
  final String color;
  final bool isDefault;
  final bool isActive;

  const GangTemplateEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.sortOrder,
    required this.color,
    this.isDefault = false,
    this.isActive = true,
  });

  /// Parse hex color string to Flutter Color.
  Color get flutterColor {
    final hex = color.replaceFirst('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return const Color(0xFF528DFF);
  }

  /// Dim (10% alpha) version of the Gang color for badge backgrounds.
  Color get dimColor => flutterColor.withValues(alpha: 0.12);

  GangTemplateEntity copyWith({
    String? id,
    String? tenantId,
    String? name,
    int? sortOrder,
    String? color,
    bool? isDefault,
    bool? isActive,
  }) {
    return GangTemplateEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      color: color ?? this.color,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GangTemplateEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'GangTemplateEntity(id: $id, name: $name, sort: $sortOrder)';
}

// ---------------------------------------------------------------------------
// OrderGangStateEntity
// ---------------------------------------------------------------------------

/// Tracks the current lifecycle state of a Gang within a specific order.
class OrderGangStateEntity {
  final String id;
  final String tenantId;
  final String ticketId;
  final String gangTemplateId;
  final GangOrderStatus status;
  final DateTime? firedAt;
  final DateTime? readyAt;
  final DateTime? servedAt;
  final DateTime createdAt;

  const OrderGangStateEntity({
    required this.id,
    required this.tenantId,
    required this.ticketId,
    required this.gangTemplateId,
    required this.status,
    required this.createdAt,
    this.firedAt,
    this.readyAt,
    this.servedAt,
  });

  OrderGangStateEntity copyWith({
    GangOrderStatus? status,
    DateTime? firedAt,
    DateTime? readyAt,
    DateTime? servedAt,
  }) {
    return OrderGangStateEntity(
      id: id,
      tenantId: tenantId,
      ticketId: ticketId,
      gangTemplateId: gangTemplateId,
      status: status ?? this.status,
      createdAt: createdAt,
      firedAt: firedAt ?? this.firedAt,
      readyAt: readyAt ?? this.readyAt,
      servedAt: servedAt ?? this.servedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderGangStateEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
