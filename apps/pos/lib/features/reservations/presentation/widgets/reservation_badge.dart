/// ReservationBadge — displayed on table cards to indicate an upcoming
/// reservation is assigned to that table.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:gastrocore_pos/features/reservations/domain/entities/reservation_entity.dart';
import 'package:gastrocore_pos/features/reservations/presentation/providers/reservation_provider.dart';

/// Shows a compact "Reserved HH:mm – Name" badge if the table has an active
/// reservation today. Returns an empty [SizedBox] when no reservation exists.
class ReservationBadge extends ConsumerWidget {
  final String tableId;

  const ReservationBadge({super.key, required this.tableId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = ref.watch(upcomingReservationsProvider);

    return upcoming.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        final now = DateTime.now();
        // Find the next active reservation for this table today
        final match = list
            .where((r) =>
                r.tableId == tableId &&
                r.isToday &&
                (r.status == ReservationStatus.pending ||
                    r.status == ReservationStatus.confirmed) &&
                r.timeEnd.isAfter(now))
            .fold<ReservationEntity?>(
              null,
              (prev, r) =>
                  prev == null || r.timeStart.isBefore(prev.timeStart)
                      ? r
                      : prev,
            );

        if (match == null) return const SizedBox.shrink();

        final timeStr = DateFormat('HH:mm').format(match.timeStart);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event,
                size: 10,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 3),
              Text(
                '$timeStr ${match.customerName.split(' ').first}',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}
