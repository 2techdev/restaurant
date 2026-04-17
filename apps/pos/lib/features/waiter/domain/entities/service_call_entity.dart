/// Waiter-raised service call ("needs water", "needs bread", …) surfaced on
/// the boss/KDS dashboards so floor staff can respond quickly.
library;

/// Canonical service-call kinds the waiter picks from. Free-form requests
/// use [ServiceCallKind.other] with a note.
enum ServiceCallKind {
  water,
  bread,
  manager,
  cleanup,
  other,
}

/// Lifecycle of a single call.
enum ServiceCallStatus {
  /// Raised by the waiter, not yet seen on the dashboard.
  pending,

  /// A receiver (boss / KDS) has acknowledged and is handling it.
  acknowledged,

  /// Resolved.
  resolved,
}

/// A single service-call row.
class ServiceCallEntity {
  final String id;
  final String tenantId;
  final String? tableId;
  final String? ticketId;
  final String waiterId;
  final String waiterName;
  final ServiceCallKind kind;
  final String? note;
  final ServiceCallStatus status;
  final DateTime createdAt;
  final DateTime? acknowledgedAt;
  final String? acknowledgedBy;

  const ServiceCallEntity({
    required this.id,
    required this.tenantId,
    required this.waiterId,
    required this.waiterName,
    required this.kind,
    required this.createdAt,
    this.tableId,
    this.ticketId,
    this.note,
    this.status = ServiceCallStatus.pending,
    this.acknowledgedAt,
    this.acknowledgedBy,
  });

  ServiceCallEntity copyWith({
    String? id,
    String? tenantId,
    String? Function()? tableId,
    String? Function()? ticketId,
    String? waiterId,
    String? waiterName,
    ServiceCallKind? kind,
    String? Function()? note,
    ServiceCallStatus? status,
    DateTime? createdAt,
    DateTime? Function()? acknowledgedAt,
    String? Function()? acknowledgedBy,
  }) {
    return ServiceCallEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      tableId: tableId != null ? tableId() : this.tableId,
      ticketId: ticketId != null ? ticketId() : this.ticketId,
      waiterId: waiterId ?? this.waiterId,
      waiterName: waiterName ?? this.waiterName,
      kind: kind ?? this.kind,
      note: note != null ? note() : this.note,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      acknowledgedAt:
          acknowledgedAt != null ? acknowledgedAt() : this.acknowledgedAt,
      acknowledgedBy:
          acknowledgedBy != null ? acknowledgedBy() : this.acknowledgedBy,
    );
  }
}

/// Short human label for a [ServiceCallKind]. Used by the quick-action button.
String serviceCallKindLabel(ServiceCallKind kind) {
  switch (kind) {
    case ServiceCallKind.water:
      return 'Water';
    case ServiceCallKind.bread:
      return 'Bread';
    case ServiceCallKind.manager:
      return 'Manager';
    case ServiceCallKind.cleanup:
      return 'Cleanup';
    case ServiceCallKind.other:
      return 'Other';
  }
}

String serviceCallKindToString(ServiceCallKind kind) => kind.name;

ServiceCallKind parseServiceCallKind(String raw) {
  return ServiceCallKind.values.firstWhere(
    (k) => k.name == raw,
    orElse: () => ServiceCallKind.other,
  );
}

String serviceCallStatusToString(ServiceCallStatus s) => switch (s) {
      ServiceCallStatus.pending => 'pending',
      ServiceCallStatus.acknowledged => 'acknowledged',
      ServiceCallStatus.resolved => 'resolved',
    };

ServiceCallStatus parseServiceCallStatus(String raw) => switch (raw) {
      'acknowledged' => ServiceCallStatus.acknowledged,
      'resolved' => ServiceCallStatus.resolved,
      _ => ServiceCallStatus.pending,
    };
