/// Domain entity for user-defined function buttons.
///
/// See the `ActionButtons` Drift table for the underlying schema.
/// `actionPayload` is a free-form map interpreted by the dispatcher according
/// to `actionType`; the repository handles JSON encoding on persistence.
library;

import 'package:flutter/material.dart';

/// Where on the POS a button renders.
enum ActionButtonPosition {
  /// Beside the 6 Schnell quick-picks at the top of the items area.
  schnellBar,

  /// Dedicated action strip below the Schnell row — the main surface.
  ticketScreen,

  /// Reserved — per-order-line contextual actions (v2).
  orderLine,

  /// Reserved — payment screen (v2).
  paymentScreen;

  String get label => switch (this) {
        ActionButtonPosition.schnellBar => 'Schnell',
        ActionButtonPosition.ticketScreen => 'Ticket',
        ActionButtonPosition.orderLine => 'Artikel',
        ActionButtonPosition.paymentScreen => 'Zahlung',
      };

  static ActionButtonPosition fromString(String s) =>
      ActionButtonPosition.values.firstWhere(
        (v) => v.name == s,
        orElse: () => ActionButtonPosition.ticketScreen,
      );
}

/// Action type — keyed by the dispatcher. Unknown types are rendered as
/// disabled tiles so a newer seed never crashes an older build.
enum ActionButtonType {
  percentDiscount,
  fixedDiscount,
  markGift,
  addNote,
  setCourse,
  printBill,
  voidItem,
  customScript;

  String get label => switch (this) {
        ActionButtonType.percentDiscount => 'Prozent-Rabatt',
        ActionButtonType.fixedDiscount => 'Fix-Rabatt',
        ActionButtonType.markGift => 'Geschenk',
        ActionButtonType.addNote => 'Notiz',
        ActionButtonType.setCourse => 'Gang ändern',
        ActionButtonType.printBill => 'Rechnung drucken',
        ActionButtonType.voidItem => 'Stornieren',
        ActionButtonType.customScript => 'Skript',
      };

  static ActionButtonType fromString(String s) =>
      ActionButtonType.values.firstWhere(
        (v) => v.name == s,
        orElse: () => ActionButtonType.addNote,
      );
}

@immutable
class ActionButtonEntity {
  const ActionButtonEntity({
    required this.id,
    required this.tenantId,
    required this.label,
    required this.position,
    required this.actionType,
    required this.actionPayload,
    this.colorValue,
    this.iconName,
    this.sortOrder = 0,
    this.isActive = true,
    this.roleFilter,
  });

  final String id;
  final String tenantId;
  final String label;
  final int? colorValue;
  final String? iconName;
  final ActionButtonPosition position;
  final ActionButtonType actionType;
  final Map<String, dynamic> actionPayload;
  final int sortOrder;
  final bool isActive;
  final List<String>? roleFilter;

  Color? get color => colorValue == null ? null : Color(colorValue!);

  ActionButtonEntity copyWith({
    String? label,
    int? colorValue,
    bool clearColor = false,
    String? iconName,
    bool clearIcon = false,
    ActionButtonPosition? position,
    ActionButtonType? actionType,
    Map<String, dynamic>? actionPayload,
    int? sortOrder,
    bool? isActive,
    List<String>? roleFilter,
    bool clearRoleFilter = false,
  }) {
    return ActionButtonEntity(
      id: id,
      tenantId: tenantId,
      label: label ?? this.label,
      colorValue: clearColor ? null : (colorValue ?? this.colorValue),
      iconName: clearIcon ? null : (iconName ?? this.iconName),
      position: position ?? this.position,
      actionType: actionType ?? this.actionType,
      actionPayload: actionPayload ?? this.actionPayload,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      roleFilter: clearRoleFilter ? null : (roleFilter ?? this.roleFilter),
    );
  }
}
