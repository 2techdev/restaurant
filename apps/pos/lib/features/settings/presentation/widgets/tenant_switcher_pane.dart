import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/tenant/active_tenant_provider.dart';
import 'package:gastrocore_pos/core/tenant/user_tenant_repository.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';

/// Settings pane: shows the active tenant and lets a multi-tenant operator
/// switch between the tenants they have been granted access to. Hidden
/// behind the `multiTenantSwitcherEnabled` flag — the parent settings
/// screen should not insert this pane unless the flag is on.
///
/// On switch the pane immediately writes the new active tenant via
/// [ActiveTenantNotifier.switchTo] and pops back to the calling screen.
/// Cloud-sync re-pull (menu / categories / modifiers) is the responsibility
/// of `activeTenantProvider`'s listener in main.dart.
class TenantSwitcherPane extends ConsumerWidget {
  const TenantSwitcherPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTenant = ref.watch(activeTenantProvider);
    final user = ref.watch(currentUserProvider);

    if (user == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Önce giriş yapın.'),
      );
    }

    return FutureBuilder<List<UserTenantAssignment>>(
      future: UserTenantRepository(ref.read(databaseProvider))
          .getTenantsForUser(user.id),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final assignments = snap.data ?? const <UserTenantAssignment>[];
        if (assignments.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Bu kullanıcıya henüz birden fazla mağaza atanmamış. '
              'Yönetici ile bağlantı kurarak ek mağaza erişimi talep edin.',
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: assignments.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final a = assignments[i];
            final isActive = a.tenantId == activeTenant;
            return ListTile(
              leading: Icon(
                isActive ? Icons.check_circle : Icons.store_outlined,
                color: isActive ? Colors.green : null,
              ),
              title: Text(a.tenantId),
              subtitle: a.roleOverride != null
                  ? Text('Rol: ${a.roleOverride}')
                  : null,
              trailing: a.isConfirmed
                  ? null
                  : const Chip(
                      label: Text('Beklemede'),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
              enabled: a.isConfirmed && !isActive,
              onTap: () async {
                await ref
                    .read(activeTenantProvider.notifier)
                    .switchTo(a.tenantId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Mağaza değiştirildi: ${a.tenantId}')),
                  );
                  Navigator.of(context).maybePop();
                }
              },
            );
          },
        );
      },
    );
  }
}

/// Post-login modal shown to operators with multiple confirmed tenant
/// assignments. Returns the chosen tenant ID; null if dismissed (caller
/// should fall back to primary).
Future<String?> showTenantPickerSheet(
  BuildContext context, {
  required List<UserTenantAssignment> tenants,
  String? initialTenantId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hangi mağazada çalışacaksın?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...tenants.where((t) => t.isConfirmed).map(
                  (t) => ListTile(
                    leading: Icon(
                      t.tenantId == initialTenantId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(t.tenantId),
                    subtitle: t.roleOverride != null
                        ? Text('Rol: ${t.roleOverride}')
                        : null,
                    onTap: () => Navigator.of(context).pop(t.tenantId),
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}
