/// In-app notification models for the Boss app.
library;

enum NotificationSeverity { info, warning, critical }

enum NotificationKind {
  systemDown,
  dailyTargetHit,
  vipArrived,
  serviceCallDelayed,
  shiftClosed,
  other,
}

class BossNotification {
  final String id;
  final NotificationKind kind;
  final NotificationSeverity severity;
  final String title;
  final String body;
  final DateTime receivedAt;
  final bool read;

  const BossNotification({
    required this.id,
    required this.kind,
    required this.severity,
    required this.title,
    required this.body,
    required this.receivedAt,
    this.read = false,
  });

  BossNotification markRead() => BossNotification(
        id: id,
        kind: kind,
        severity: severity,
        title: title,
        body: body,
        receivedAt: receivedAt,
        read: true,
      );
}
