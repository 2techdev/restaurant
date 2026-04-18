import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_boss/features/notifications/notification_models.dart';
import 'package:gastrocore_boss/features/notifications/notifications_controller.dart';

void main() {
  group('NotificationsController', () {
    test('seed state has 2 unread notifications', () {
      final c = NotificationsController();
      addTearDown(c.dispose);

      expect(c.state.items, hasLength(2));
      expect(c.state.unreadCount, 2);
      expect(c.state.enabled, isTrue);
    });

    test('push prepends a notification when enabled', () {
      final c = NotificationsController();
      addTearDown(c.dispose);

      c.push(BossNotification(
        id: 'x1',
        kind: NotificationKind.systemDown,
        severity: NotificationSeverity.critical,
        title: 'Sistem',
        body: 'Test',
        receivedAt: DateTime.now(),
      ));
      expect(c.state.items.first.id, 'x1');
      expect(c.state.unreadCount, 3);
    });

    test('push is ignored when disabled', () {
      final c = NotificationsController();
      addTearDown(c.dispose);

      c.setEnabled(false);
      c.push(BossNotification(
        id: 'x1',
        kind: NotificationKind.systemDown,
        severity: NotificationSeverity.critical,
        title: 'Sistem',
        body: 'Test',
        receivedAt: DateTime.now(),
      ));
      expect(c.state.items, hasLength(2));
    });

    test('markAllRead drops unread count to 0', () {
      final c = NotificationsController();
      addTearDown(c.dispose);

      c.markAllRead();
      expect(c.state.unreadCount, 0);
    });

    test('dismiss removes by id', () {
      final c = NotificationsController();
      addTearDown(c.dispose);

      final firstId = c.state.items.first.id;
      c.dismiss(firstId);
      expect(c.state.items.any((n) => n.id == firstId), isFalse);
    });

    test('clearAll empties the list', () {
      final c = NotificationsController();
      addTearDown(c.dispose);

      c.clearAll();
      expect(c.state.items, isEmpty);
      expect(c.state.unreadCount, 0);
    });
  });
}
