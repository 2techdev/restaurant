/// ReservationListScreen: today's and upcoming reservations.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/features/reservations/domain/entities/reservation_entity.dart';
import 'package:gastrocore_pos/features/reservations/presentation/providers/reservation_provider.dart';
import 'package:gastrocore_pos/features/reservations/presentation/widgets/reservation_status_chip.dart';

class ReservationListScreen extends ConsumerWidget {
  const ReservationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = ref.watch(upcomingReservationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reservations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Calendar',
            onPressed: () => context.push(AppRoutes.reservationCalendar),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Reservation'),
        onPressed: () => context.push(AppRoutes.reservationNew),
      ),
      body: upcoming.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_available,
                      size: 64, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('No upcoming reservations',
                      style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            );
          }

          // Group by date
          final grouped = <String, List<ReservationEntity>>{};
          for (final r in list) {
            final key = DateFormat('yyyy-MM-dd').format(r.date);
            grouped.putIfAbsent(key, () => []).add(r);
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: grouped.length,
            itemBuilder: (context, idx) {
              final dateKey = grouped.keys.elementAt(idx);
              final reservations = grouped[dateKey]!;
              final date = DateTime.parse(dateKey);
              final isToday = reservations.first.isToday;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      isToday
                          ? 'Today'
                          : DateFormat('EEEE, d MMMM').format(date),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: isToday
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  ...reservations.map(
                    (r) => _ReservationTile(
                      reservation: r,
                      onTap: () => context.push(
                        AppRoutes.reservationDetail(r.id),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ReservationTile extends StatelessWidget {
  final ReservationEntity reservation;
  final VoidCallback onTap;

  const _ReservationTile({required this.reservation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            reservation.customerName.isNotEmpty
                ? reservation.customerName[0].toUpperCase()
                : '?',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(reservation.customerName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${timeFormat.format(reservation.timeStart)} – '
          '${timeFormat.format(reservation.timeEnd)}  •  '
          '${reservation.partySize} pax',
        ),
        trailing: ReservationStatusChip(status: reservation.status),
      ),
    );
  }
}
