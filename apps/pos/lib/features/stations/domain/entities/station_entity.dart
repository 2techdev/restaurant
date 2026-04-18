/// Kitchen station domain entity.
///
/// A station is a physical or logical cooking area — e.g. Hot, Cold, Grill,
/// Dessert, Bar. The [code] matches [KitchenTicket.printerGroup] so ticket
/// routing and KDS filtering operate on the same identifier.
library;

import 'package:flutter/material.dart';

class StationEntity {
  final String id;
  final String tenantId;

  /// Stable lowercase code used as printer-group / filter key.
  final String code;

  /// Display name.
  final String name;

  /// Material icon code point (stored as string for portability). Falls back
  /// to [Icons.restaurant] when null or unparsable.
  final String? icon;

  /// Optional hex accent color, e.g. '#F97316'.
  final String? color;

  final int sortOrder;
  final bool isDefault;
  final bool isActive;

  const StationEntity({
    required this.id,
    required this.tenantId,
    required this.code,
    required this.name,
    required this.sortOrder,
    this.icon,
    this.color,
    this.isDefault = false,
    this.isActive = true,
  });

  IconData get iconData {
    final raw = icon;
    if (raw == null) return Icons.restaurant;
    final parsed = int.tryParse(raw);
    if (parsed == null) return Icons.restaurant;
    return IconData(parsed, fontFamily: 'MaterialIcons');
  }

  Color? get accentColor {
    final hex = color;
    if (hex == null) return null;
    final clean = hex.replaceFirst('#', '');
    if (clean.length != 6) return null;
    final value = int.tryParse(clean, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }

  StationEntity copyWith({
    String? code,
    String? name,
    String? icon,
    String? color,
    int? sortOrder,
    bool? isDefault,
    bool? isActive,
  }) {
    return StationEntity(
      id: id,
      tenantId: tenantId,
      code: code ?? this.code,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StationEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
