/// Header indicator that surfaces open service calls on the POS home screen.
///
/// Waiters raise calls from their app; the POS/manager side needs to see every
/// open call so the floor can respond quickly. Renders a bell icon with a red
/// count badge when there are unresolved calls. Tapping opens a popup listing
/// each call (kind · table · age · waiter) with Acknowledge / Resolve actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/waiter/domain/entities/service_call_entity.dart';
import 'package:gastrocore_pos/features/waiter/presentation/providers/waiter_provider.dart';

/// Compact bell icon + unresolved-count badge for the POS home header.
class ServiceCallBell extends ConsumerWidget {
  const ServiceCallBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callsAsync = ref.watch(activeServiceCallsProvider);
    final calls = callsAsync.valueOrNull ?? const <ServiceCallEntity>[];
    final count = calls.length;

    return Tooltip(
      message: count == 0 ? 'No open service calls' : '$count open service call${count == 1 ? '' : 's'}',
      child: InkWell(
        key: const Key('home.serviceCallBell'),
        onTap: () => _openInbox(context, calls),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                count == 0
                    ? Icons.notifications_none_outlined
                    : Icons.notifications_active,
                size: 24,
                color: count == 0 ? AppColors.textSecondary : AppColors.orange,
              ),
              if (count > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openInbox(BuildContext context, List<ServiceCallEntity> calls) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ServiceCallInbox(calls: calls),
    );
  }
}

class _ServiceCallInbox extends ConsumerWidget {
  const _ServiceCallInbox({required this.calls});
  final List<ServiceCallEntity> calls;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (calls.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text(
            'No open service calls',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: calls.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (_, i) => _CallTile(call: calls[i]),
      ),
    );
  }
}

class _CallTile extends ConsumerWidget {
  const _CallTile({required this.call});
  final ServiceCallEntity call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acknowledged = call.status == ServiceCallStatus.acknowledged;
    final age = DateTime.now().difference(call.createdAt);
    final ageLabel = _ageLabel(age);

    return ListTile(
      leading: Icon(
        _iconFor(call.kind),
        color: acknowledged ? AppColors.textSecondary : AppColors.orange,
      ),
      title: Text(
        serviceCallKindLabel(call.kind),
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '${call.waiterName}${call.note != null ? " · ${call.note}" : ""} · $ageLabel',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!acknowledged)
            TextButton(
              onPressed: () => _ack(ref, call.id),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.orange,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Ack',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          TextButton(
            onPressed: () => _resolve(ref, call.id, context),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Done',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _ack(WidgetRef ref, String id) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    await ref
        .read(serviceCallRepositoryProvider)
        .acknowledge(id: id, byUserId: user.id);
  }

  Future<void> _resolve(WidgetRef ref, String id, BuildContext context) async {
    await ref.read(serviceCallRepositoryProvider).resolve(id);
    // If this was the last open call, close the sheet.
    final remaining = ref.read(activeServiceCallsProvider).valueOrNull ?? const [];
    if (remaining.length <= 1 && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  IconData _iconFor(ServiceCallKind k) {
    switch (k) {
      case ServiceCallKind.water:
        return Icons.local_drink_outlined;
      case ServiceCallKind.bread:
        return Icons.bakery_dining_outlined;
      case ServiceCallKind.manager:
        return Icons.supervisor_account_outlined;
      case ServiceCallKind.cleanup:
        return Icons.cleaning_services_outlined;
      case ServiceCallKind.other:
        return Icons.notifications_active_outlined;
    }
  }

  String _ageLabel(Duration d) {
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}
