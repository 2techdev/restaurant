/// Home shell with bottom navigation: Live · Z-Report · Staff · Settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';
import '../notifications/notifications_controller.dart';
import '../notifications/notifications_sheet.dart';

class HomeShell extends ConsumerStatefulWidget {
  final Widget child;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const HomeShell({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final ownerName = auth is AuthAuthenticated ? auth.session.user.name : '';
    final unread = ref.watch(unreadCountProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            const Text('Boss'),
            const SizedBox(width: 8),
            if (ownerName.isNotEmpty)
              Text(
                '· $ownerName',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
          ],
        ),
        actions: [
          _NotificationBell(unread: unread),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış',
            onPressed: () =>
                ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.surface,
        selectedIndex: widget.currentIndex,
        onDestinationSelected: widget.onTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            label: 'Canlı',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long),
            label: 'Z-Rapor',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'Personel',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Ayarlar',
          ),
        ],
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final int unread;
  const _NotificationBell({required this.unread});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          key: const Key('boss-notif-bell'),
          icon: const Icon(Icons.notifications_none),
          tooltip: 'Bildirimler',
          onPressed: () => showNotificationsSheet(context),
        ),
        if (unread > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(999),
              ),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
