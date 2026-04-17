/// Home shell with bottom navigation: Live · Z-Report · Staff · Settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';

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
