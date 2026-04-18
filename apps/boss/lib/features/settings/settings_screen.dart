/// Settings — notification toggle, logout, version.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';

import '../auth/auth_controller.dart';
import '../notifications/notifications_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notif = ref.watch(notificationsControllerProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'Bildirimler',
          child: SwitchListTile(
            key: const Key('settings-notif-toggle'),
            value: notif.enabled,
            onChanged: (v) => ref
                .read(notificationsControllerProvider.notifier)
                .setEnabled(v),
            title: const Text(
              'Uygulama içi bildirimler',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            subtitle: const Text(
              'Kritik olaylar için rozet ve bildirim listesi.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            activeThumbColor: AppColors.accent,
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Hesap',
          child: ListTile(
            leading: const Icon(Icons.logout, color: AppColors.red),
            title: const Text(
              'Çıkış yap',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            onTap: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Uygulama',
          child: const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text(
              'Sürüm',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            trailing: Text(
              '0.1.0 (Sprint 1)',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: child,
        ),
      ],
    );
  }
}
