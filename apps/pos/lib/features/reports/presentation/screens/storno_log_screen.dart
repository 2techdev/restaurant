/// Storno (İPTAL) log screen — pilot audit surface.
///
/// Renders every [StornoLogEntry] collected since app start as a simple
/// reverse-chronological ListView. Auditors can scan who voided which
/// ticket, for what reason, and for how much.
///
/// Backed by the in-memory [stornoLogProvider]. A future migration to a
/// Drift-backed table would swap the provider without changing this view.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/storno_log_provider.dart';

class StornoLogScreen extends ConsumerWidget {
  const StornoLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(stornoLogProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: const Text('İptal Günlüğü'),
        backgroundColor: AppColors.surfaceContainerLow,
      ),
      body: entries.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _StornoRow(entry: entries[i]),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: AppColors.navText),
            SizedBox(height: 12),
            Text(
              'Henüz iptal kaydı yok.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _StornoRow extends StatelessWidget {
  final StornoLogEntry entry;

  const _StornoRow({required this.entry});

  String _formatTimestamp(DateTime ts) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${ts.year}-${two(ts.month)}-${two(ts.day)} '
        '${two(ts.hour)}:${two(ts.minute)}';
  }

  String _formatAmount(int cents) {
    return 'CHF ${(cents / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: AppColors.red,
        foregroundColor: Colors.white,
        child: Icon(Icons.block_rounded),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Sipariş ${entry.orderNumber}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            _formatAmount(entry.amountCents),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text('Neden: ${entry.reason}'),
          const SizedBox(height: 2),
          Text(
            '${entry.userName} • ${_formatTimestamp(entry.timestamp)}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
      isThreeLine: true,
    );
  }
}
