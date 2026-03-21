/// Domain entities for the reservation feature.
library;

enum ReservationStatus {
  pending,
  confirmed,
  seated,
  cancelled,
  noShow;

  String get value => switch (this) {
        ReservationStatus.pending => 'pending',
        ReservationStatus.confirmed => 'confirmed',
        ReservationStatus.seated => 'seated',
        ReservationStatus.cancelled => 'cancelled',
        ReservationStatus.noShow => 'no_show',
      };

  static ReservationStatus fromString(String value) => switch (value) {
        'confirmed' => ReservationStatus.confirmed,
        'seated' => ReservationStatus.seated,
        'cancelled' => ReservationStatus.cancelled,
        'no_show' => ReservationStatus.noShow,
        _ => ReservationStatus.pending,
      };
}

enum ReservationChannel {
  walkIn,
  online,
  phone;

  String get value => switch (this) {
        ReservationChannel.walkIn => 'walk_in',
        ReservationChannel.online => 'online',
        ReservationChannel.phone => 'phone',
      };

  static ReservationChannel fromString(String value) => switch (value) {
        'online' => ReservationChannel.online,
        'phone' => ReservationChannel.phone,
        _ => ReservationChannel.walkIn,
      };
}

class ReservationEntity {
  final String id;
  final String tenantId;
  final String customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String? tableId;
  final DateTime date;
  final DateTime timeStart;
  final DateTime timeEnd;
  final int partySize;
  final ReservationStatus status;
  final String? notes;
  final ReservationChannel channel;
  final DateTime createdAt;
  final String? createdBy;

  const ReservationEntity({
    required this.id,
    required this.tenantId,
    required this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.tableId,
    required this.date,
    required this.timeStart,
    required this.timeEnd,
    required this.partySize,
    required this.status,
    this.notes,
    required this.channel,
    required this.createdAt,
    this.createdBy,
  });

  ReservationEntity copyWith({
    String? id,
    String? tenantId,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? tableId,
    DateTime? date,
    DateTime? timeStart,
    DateTime? timeEnd,
    int? partySize,
    ReservationStatus? status,
    String? notes,
    ReservationChannel? channel,
    DateTime? createdAt,
    String? createdBy,
  }) {
    return ReservationEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerEmail: customerEmail ?? this.customerEmail,
      tableId: tableId ?? this.tableId,
      date: date ?? this.date,
      timeStart: timeStart ?? this.timeStart,
      timeEnd: timeEnd ?? this.timeEnd,
      partySize: partySize ?? this.partySize,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      channel: channel ?? this.channel,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  bool get isActive =>
      status == ReservationStatus.pending ||
      status == ReservationStatus.confirmed;

  bool get isUpcoming => isActive && timeStart.isAfter(DateTime.now());

  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReservationEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ReservationEntity(id: $id, customer: $customerName, status: $status)';
}
