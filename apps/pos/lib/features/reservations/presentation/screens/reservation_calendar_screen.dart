/// ReservationCalendarScreen: daily/weekly calendar view with table occupancy.
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

class ReservationCalendarScreen extends ConsumerStatefulWidget {
  const ReservationCalendarScreen({super.key});

  @override
  ConsumerState<ReservationCalendarScreen> createState() =>
      _ReservationCalendarScreenState();
}

class _ReservationCalendarScreenState
    extends ConsumerState<ReservationCalendarScreen> {
  bool _weekMode = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedDate = ref.watch(selectedReservationDateProvider);
    final reservationsAsync = ref.watch(reservationsForDateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reservationCalendar),
        actions: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(l10n.reservationViewDay)),
              ButtonSegment(value: true, label: Text(l10n.reservationViewWeek)),
            ],
            selected: {_weekMode},
            onSelectionChanged: (v) => setState(() => _weekMode = v.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l10n.reservationNew),
        onPressed: () => context.push(AppRoutes.reservationNew),
      ),
      body: Column(
        children: [
          _DateNav(
            selectedDate: selectedDate,
            weekMode: _weekMode,
            onDateChanged: (d) => ref
                .read(selectedReservationDateProvider.notifier)
                .state = d,
          ),
          const Divider(height: 1),
          Expanded(
            child: reservationsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(e.toString())),
              data: (list) => _weekMode
                  ? _WeekView(
                      anchor: selectedDate,
                      onDayTap: (d) {
                        ref
                            .read(selectedReservationDateProvider.notifier)
                            .state = d;
                        setState(() => _weekMode = false);
                      },
                    )
                  : _DayView(reservations: list),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date navigation bar
// ---------------------------------------------------------------------------

class _DateNav extends StatelessWidget {
  final DateTime selectedDate;
  final bool weekMode;
  final ValueChanged<DateTime> onDateChanged;

  const _DateNav({
    required this.selectedDate,
    required this.weekMode,
    required this.onDateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = weekMode
        ? DateFormat('MMM yyyy')
        : DateFormat('EEEE, d MMMM yyyy');
    final stepDays = weekMode ? 7 : 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () =>
                onDateChanged(selectedDate.subtract(Duration(days: stepDays))),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2099),
                );
                if (picked != null) onDateChanged(picked);
              },
              child: Text(
                fmt.format(selectedDate),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () =>
                onDateChanged(selectedDate.add(Duration(days: stepDays))),
          ),
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              final now = DateTime.now();
              onDateChanged(DateTime(now.year, now.month, now.day));
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day view — timeline of hourly slots 10:00–24:00
// ---------------------------------------------------------------------------

class _DayView extends StatelessWidget {
  final List<ReservationEntity> reservations;

  const _DayView({required this.reservations});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (reservations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(l10n.reservationNoReservations,
                style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: reservations.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        final r = reservations[i];
        return _TimelineItem(reservation: r);
      },
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final ReservationEntity reservation;

  const _TimelineItem({required this.reservation});

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('HH:mm');
    return ListTile(
      leading: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(timeFmt.format(reservation.timeStart),
              style: Theme.of(context).textTheme.labelLarge),
          Text(timeFmt.format(reservation.timeEnd),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ],
      ),
      title: Text(reservation.customerName,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${reservation.partySize} pax'
          '${reservation.tableId != null ? " • Table ${reservation.tableId}" : ""}'),
      trailing: ReservationStatusChip(
        status: reservation.status,
        compact: true,
      ),
      onTap: () => context.push(AppRoutes.reservationDetail(reservation.id)),
    );
  }
}

// ---------------------------------------------------------------------------
// Week view — 7-day grid
// ---------------------------------------------------------------------------

class _WeekView extends ConsumerWidget {
  final DateTime anchor;
  final ValueChanged<DateTime> onDayTap;

  const _WeekView({required this.anchor, required this.onDayTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Build week starting on Monday
    final monday = anchor.subtract(Duration(days: anchor.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.8,
      ),
      itemCount: 7,
      itemBuilder: (context, i) {
        final day = days[i];
        final isToday = _isToday(day);
        final isSelected = _isSameDay(day, anchor);

        return _WeekDayCell(
          day: day,
          isToday: isToday,
          isSelected: isSelected,
          onTap: () => onDayTap(day),
        );
      },
    );
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _WeekDayCell extends ConsumerWidget {
  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  const _WeekDayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = ref.watch(upcomingReservationsProvider);
    final count = upcoming.maybeWhen(
      data: (list) => list
          .where((r) =>
              r.date.year == day.year &&
              r.date.month == day.month &&
              r.date.day == day.day)
          .length,
      orElse: () => 0,
    );

    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : isToday
                  ? colorScheme.surfaceContainerHighest
                  : colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline,
            width: isSelected ? 2 : 0.5,
          ),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('E').format(day),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.outline,
                  ),
            ),
            Text(
              '${day.day}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight:
                        isToday ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? colorScheme.primary : null,
                  ),
            ),
            if (count > 0)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
