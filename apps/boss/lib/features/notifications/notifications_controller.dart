/// In-app notification centre state — list + unread count + enabled flag.
///
/// TODO(boss-sprint2): swap the simulated event feed for a real server-sent
/// event / WebSocket channel (`/ws/notifications`) once the backend exposes
/// it. FCM / APNs wiring lands in Sprint 3 when push is prioritised.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_models.dart';

class NotificationsState {
  final List<BossNotification> items;
  final bool enabled;

  const NotificationsState({required this.items, required this.enabled});

  int get unreadCount => items.where((n) => !n.read).length;

  NotificationsState copyWith({
    List<BossNotification>? items,
    bool? enabled,
  }) =>
      NotificationsState(
        items: items ?? this.items,
        enabled: enabled ?? this.enabled,
      );

  factory NotificationsState.initial() => NotificationsState(
        items: [
          BossNotification(
            id: 'n-seed-1',
            kind: NotificationKind.vipArrived,
            severity: NotificationSeverity.info,
            title: 'VIP müşteri geldi',
            body: 'Masa 4 — Bay Weber (son 90 günde 6 ziyaret).',
            receivedAt: DateTime.now().subtract(const Duration(minutes: 2)),
          ),
          BossNotification(
            id: 'n-seed-2',
            kind: NotificationKind.serviceCallDelayed,
            severity: NotificationSeverity.warning,
            title: 'Servis çağrısı 5dk+',
            body: 'Masa 12 garson çağırdı, 6 dakikadır bekliyor.',
            receivedAt: DateTime.now().subtract(const Duration(minutes: 8)),
          ),
        ],
        enabled: true,
      );
}

class NotificationsController extends StateNotifier<NotificationsState> {
  Timer? _simulator;

  NotificationsController() : super(NotificationsState.initial()) {
    _startSimulator();
  }

  void _startSimulator() {
    _simulator?.cancel();
    // Emit a synthetic "daily target" event after 25s so reviewers can see
    // the badge increment. Real feed replaces this in Sprint 2.
    _simulator = Timer(const Duration(seconds: 25), () {
      if (!mounted) return;
      push(
        BossNotification(
          id: 'n-${DateTime.now().millisecondsSinceEpoch}',
          kind: NotificationKind.dailyTargetHit,
          severity: NotificationSeverity.info,
          title: 'Günlük hedef aşıldı',
          body: 'Bugünkü ciro günlük hedefin %100 üzerine çıktı.',
          receivedAt: DateTime.now(),
        ),
      );
    });
  }

  void push(BossNotification n) {
    if (!state.enabled) return;
    state = state.copyWith(items: [n, ...state.items]);
  }

  void markAllRead() {
    state = state.copyWith(
      items: state.items.map((n) => n.markRead()).toList(),
    );
  }

  void markRead(String id) {
    state = state.copyWith(
      items: [
        for (final n in state.items)
          if (n.id == id) n.markRead() else n,
      ],
    );
  }

  void dismiss(String id) {
    state = state.copyWith(
      items: state.items.where((n) => n.id != id).toList(),
    );
  }

  void clearAll() {
    state = state.copyWith(items: const []);
  }

  void setEnabled(bool enabled) {
    state = state.copyWith(enabled: enabled);
  }

  @override
  void dispose() {
    _simulator?.cancel();
    super.dispose();
  }
}

final notificationsControllerProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>(
  (ref) => NotificationsController(),
);

final unreadCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsControllerProvider).unreadCount,
);
