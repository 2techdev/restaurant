/// ReservationDetailScreen: view details, change status, edit or delete.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/features/reservations/domain/entities/reservation_entity.dart';
import 'package:gastrocore_pos/features/reservations/presentation/providers/reservation_provider.dart';
import 'package:gastrocore_pos/features/reservations/presentation/widgets/reservation_status_chip.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

class ReservationDetailScreen extends ConsumerWidget {
  final String reservationId;

  const ReservationDetailScreen({super.key, required this.reservationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final reservationAsync = ref.watch(reservationByIdProvider(reservationId));
    final notifier = ref.read(reservationManagementProvider.notifier);

    return reservationAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(e.toString())),
      ),
      data: (reservation) {
        if (reservation == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(l10n.statusNoData)),
          );
        }
        return _DetailBody(
          reservation: reservation,
          l10n: l10n,
          notifier: notifier,
        );
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  final ReservationEntity reservation;
  final AppLocalizations l10n;
  final ReservationManagementNotifier notifier;

  const _DetailBody({
    required this.reservation,
    required this.l10n,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEEE, d MMMM yyyy');
    final timeFmt = DateFormat('HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Text(reservation.customerName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: l10n.actionEdit,
            onPressed: () => context.push(
              AppRoutes.reservationEdit(reservation.id),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.actionDelete,
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status chip + channel
          Row(
            children: [
              ReservationStatusChip(status: reservation.status),
              const SizedBox(width: 8),
              Chip(
                label: Text(_channelLabel(reservation.channel)),
                avatar: const Icon(Icons.record_voice_over, size: 14),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Date/time card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    icon: Icons.calendar_today,
                    label: 'Date',
                    value: dateFmt.format(reservation.date),
                  ),
                  _InfoRow(
                    icon: Icons.schedule,
                    label: 'Time',
                    value:
                        '${timeFmt.format(reservation.timeStart)} – ${timeFmt.format(reservation.timeEnd)}',
                  ),
                  _InfoRow(
                    icon: Icons.people,
                    label: 'Party Size',
                    value: '${reservation.partySize} pax',
                  ),
                  if (reservation.tableId != null)
                    _InfoRow(
                      icon: Icons.table_restaurant,
                      label: 'Table',
                      value: reservation.tableId!,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Contact card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    icon: Icons.person,
                    label: 'Guest Name',
                    value: reservation.customerName,
                  ),
                  if (reservation.customerPhone != null)
                    _InfoRow(
                      icon: Icons.phone,
                      label: 'Phone',
                      value: reservation.customerPhone!,
                    ),
                  if (reservation.customerEmail != null)
                    _InfoRow(
                      icon: Icons.email,
                      label: 'Email',
                      value: reservation.customerEmail!,
                    ),
                ],
              ),
            ),
          ),

          if (reservation.notes != null && reservation.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Notes',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(reservation.notes!),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Status actions
          Text('Change Status',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _StatusActions(reservation: reservation, notifier: notifier),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.confirmDelete),
        content: Text(l10n.confirmDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => ctx.pop(true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await notifier.deleteReservation(reservation.id);
      if (context.mounted) context.pop();
    }
  }

  String _channelLabel(ReservationChannel c) =>
      switch (c) {
        ReservationChannel.walkIn => 'Walk-In',
        ReservationChannel.online => 'Online',
        ReservationChannel.phone => 'Phone',
      };
}

class _StatusActions extends StatelessWidget {
  final ReservationEntity reservation;
  final ReservationManagementNotifier notifier;

  const _StatusActions({
    required this.reservation,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    final status = reservation.status;
    final id = reservation.id;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (status == ReservationStatus.pending)
          FilledButton.icon(
            icon: const Icon(Icons.check_circle),
            label: const Text('Confirm'),
            onPressed: () => notifier.markConfirmed(id),
          ),
        if (status == ReservationStatus.confirmed)
          FilledButton.icon(
            icon: const Icon(Icons.restaurant),
            label: const Text('Seat Guests'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            onPressed: () => notifier.markSeated(id),
          ),
        if (status != ReservationStatus.cancelled &&
            status != ReservationStatus.noShow &&
            status != ReservationStatus.seated)
          OutlinedButton.icon(
            icon: const Icon(Icons.person_off),
            label: const Text('No-Show'),
            onPressed: () => notifier.markNoShow(id),
          ),
        if (status != ReservationStatus.cancelled &&
            status != ReservationStatus.seated)
          OutlinedButton.icon(
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => notifier.markCancelled(id),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Text('$label: ',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.outline,
                fontSize: 13,
              )),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
