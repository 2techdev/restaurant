/// Waiter "Hazır!" notifier — polls waiterActiveOrdersProvider and pops a
/// floating banner the first time an order's status transitions to
/// [TicketStatus.ready]. Replaces the previous behaviour where readiness
/// was only visible if the waiter manually pulled to refresh.
///
/// Why polling and not SSE: the existing waiter app already runs through
/// WebSocketSyncClient (see lib/waiter_app.dart), but there is no dedicated
/// "ticket-ready" channel yet on the server side — adding one would mean
/// touching the Go push pipeline and the receiver code-path mid-sprint.
/// A 15-second Riverpod invalidate cycle is cheap (the query is local
/// Drift, no network round-trip), gets the operator a notification inside
/// a kitchen-relevant time window, and keeps the change tightly scoped to
/// the waiter feature. A direct SSE upgrade is queued as a follow-up.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/waiter/presentation/providers/waiter_provider.dart';

/// Wraps [child] and surfaces a floating SnackBar whenever a ticket the
/// waiter owns transitions into [TicketStatus.ready]. Drop this widget
/// inside the waiter shell once, near the root, so banners survive tab
/// switches.
class WaiterReadyListener extends ConsumerStatefulWidget {
  const WaiterReadyListener({super.key, required this.child});

  final Widget child;

  /// How often to re-pull the active-orders list. 15s is fast enough for
  /// kitchen workflow (an order that turns ready is rarely served instantly)
  /// and slow enough that the Drift query churn is invisible.
  static const _pollInterval = Duration(seconds: 15);

  @override
  ConsumerState<WaiterReadyListener> createState() =>
      _WaiterReadyListenerState();
}

class _WaiterReadyListenerState extends ConsumerState<WaiterReadyListener> {
  /// IDs of tickets the listener has already announced as ready. Prevents
  /// the same ticket from triggering a banner on every poll cycle while it
  /// still sits in the "ready" bucket waiting for the waiter to serve it.
  final Set<String> _announced = <String>{};

  /// Tracks the previously seen status per ticket id so the listener only
  /// fires when a ticket truly *transitions* into ready (rather than the
  /// listener seeing an already-ready ticket on first mount and emitting
  /// a banner the operator never asked for).
  final Map<String, TicketStatus> _lastStatus = <String, TicketStatus>{};

  Timer? _poller;
  bool _firstSnapshotSeen = false;

  @override
  void initState() {
    super.initState();
    _poller = Timer.periodic(
      WaiterReadyListener._pollInterval,
      (_) {
        if (mounted) {
          ref.invalidate(waiterActiveOrdersProvider);
        }
      },
    );
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<TicketEntity>>>(
      waiterActiveOrdersProvider,
      (prev, next) {
        next.whenData(_handleTickets);
      },
    );
    return widget.child;
  }

  void _handleTickets(List<TicketEntity> tickets) {
    // First snapshot after login — record current status without firing.
    // The waiter probably already saw any "ready" badges in the list and
    // doesn't want a retroactive ping for every backlog item.
    if (!_firstSnapshotSeen) {
      for (final t in tickets) {
        _lastStatus[t.id] = t.status;
        if (t.status == TicketStatus.ready) {
          _announced.add(t.id);
        }
      }
      _firstSnapshotSeen = true;
      return;
    }

    for (final ticket in tickets) {
      final prev = _lastStatus[ticket.id];
      _lastStatus[ticket.id] = ticket.status;

      if (ticket.status != TicketStatus.ready) {
        // If the ticket leaves "ready" (e.g. served), clear the dedupe
        // record so a second cycle of ready→served→ready still fires.
        _announced.remove(ticket.id);
        continue;
      }
      if (_announced.contains(ticket.id)) continue;
      if (prev == TicketStatus.ready) continue; // unchanged

      _announced.add(ticket.id);
      _announceReady(ticket);
    }
  }

  void _announceReady(TicketEntity ticket) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.notifications_active, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Sipariş #${ticket.orderNumber} hazır!',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
