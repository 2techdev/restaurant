/// Modal bottom sheet showing all notifications.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';
import 'package:intl/intl.dart';

import 'notification_models.dart';
import 'notifications_controller.dart';

Future<void> showNotificationsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _NotificationsSheet(),
  );
}

class _NotificationsSheet extends ConsumerWidget {
  const _NotificationsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(notificationsControllerProvider);
    final ctrl = ref.read(notificationsControllerProvider.notifier);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          _Header(
            unread: s.unreadCount,
            onMarkAll: ctrl.markAllRead,
            onClearAll: ctrl.clearAll,
          ),
          Expanded(
            child: s.items.isEmpty
                ? const EmptyState(
                    icon: Icons.notifications_none,
                    title: 'Bildirim yok',
                    subtitle: 'Kritik olaylar burada listelenecek.',
                  )
                : ListView.builder(
                    controller: scroll,
                    itemCount: s.items.length,
                    itemBuilder: (_, i) {
                      final n = s.items[i];
                      return _Tile(
                        notification: n,
                        onRead: () => ctrl.markRead(n.id),
                        onDismiss: () => ctrl.dismiss(n.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int unread;
  final VoidCallback onMarkAll;
  final VoidCallback onClearAll;

  const _Header({
    required this.unread,
    required this.onMarkAll,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          const Text(
            'Bildirimler',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$unread okunmamış',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                ),
              ),
            ),
          const Spacer(),
          TextButton(
            key: const Key('notif-mark-all'),
            onPressed: onMarkAll,
            child: const Text('Hepsini okundu yap'),
          ),
          IconButton(
            key: const Key('notif-clear-all'),
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: onClearAll,
            tooltip: 'Temizle',
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final BossNotification notification;
  final VoidCallback onRead;
  final VoidCallback onDismiss;

  const _Tile({
    required this.notification,
    required this.onRead,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(notification.severity);
    final timeFmt = DateFormat.Hm();
    return Dismissible(
      key: Key('notif-${notification.id}'),
      background: Container(color: AppColors.redDim),
      onDismissed: (_) => onDismiss(),
      child: InkWell(
        onTap: onRead,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, right: 12),
                decoration: BoxDecoration(
                  color: notification.read ? AppColors.textDim : color,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: notification.read
                                  ? FontWeight.w400
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          timeFmt.format(notification.receivedAt),
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _severityColor(NotificationSeverity s) {
    switch (s) {
      case NotificationSeverity.info:
        return AppColors.accent;
      case NotificationSeverity.warning:
        return AppColors.orange;
      case NotificationSeverity.critical:
        return AppColors.red;
    }
  }
}
