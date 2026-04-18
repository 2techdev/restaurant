/// Fine-dining course (Gang) — fixed three positions.
///
/// Labels are intentionally fixed to "Gang 1", "Gang 2", "Gang 3"; there is
/// no per-tenant override. Ordering between gangs is by [position].
library;

/// Three-course fine-dining progression.
enum Gang {
  first(1),
  second(2),
  third(3);

  const Gang(this.position);

  /// 1-based position used for routing to the kitchen (KDS).
  final int position;

  /// Canonical display label. Fixed — do not parametrise.
  String get displayLabel => 'Gang $position';

  static Gang? fromPosition(int p) => switch (p) {
        1 => Gang.first,
        2 => Gang.second,
        3 => Gang.third,
        _ => null,
      };
}

/// A Gang slot associated with a ticket / order item. Kept as an entity so
/// consumers can attach metadata (e.g. fired-at timestamps) without changing
/// the enum.
class GangEntity {
  final Gang gang;

  /// Timestamp the waiter "fired" the gang to the kitchen. Null before fire.
  final DateTime? firedAt;

  /// Timestamp the kitchen finished the gang.
  final DateTime? readyAt;

  const GangEntity({
    required this.gang,
    this.firedAt,
    this.readyAt,
  });

  int get position => gang.position;

  String get displayLabel => gang.displayLabel;

  bool get isFired => firedAt != null;

  bool get isReady => readyAt != null;

  factory GangEntity.fromJson(Map<String, dynamic> json) => GangEntity(
        gang: Gang.fromPosition((json['position'] as num?)?.toInt() ?? 1) ??
            Gang.first,
        firedAt: json['fired_at'] != null
            ? DateTime.parse(json['fired_at'] as String)
            : null,
        readyAt: json['ready_at'] != null
            ? DateTime.parse(json['ready_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'position': gang.position,
        if (firedAt != null) 'fired_at': firedAt!.toIso8601String(),
        if (readyAt != null) 'ready_at': readyAt!.toIso8601String(),
      };

  GangEntity copyWith({
    Gang? gang,
    DateTime? Function()? firedAt,
    DateTime? Function()? readyAt,
  }) {
    return GangEntity(
      gang: gang ?? this.gang,
      firedAt: firedAt != null ? firedAt() : this.firedAt,
      readyAt: readyAt != null ? readyAt() : this.readyAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GangEntity &&
          runtimeType == other.runtimeType &&
          gang == other.gang &&
          firedAt == other.firedAt &&
          readyAt == other.readyAt;

  @override
  int get hashCode => Object.hash(gang, firedAt, readyAt);

  @override
  String toString() =>
      'GangEntity(${gang.displayLabel}${isFired ? ', fired' : ''}${isReady ? ', ready' : ''})';
}
