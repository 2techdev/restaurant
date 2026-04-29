/// In-memory storno (İPTAL) audit log for pilot deployments.
///
/// The full void repository (`void_repository_impl.dart`) is reserved for
/// the manager-approved void flow. The action-rail İPTAL button used during
/// early service does not require a manager override, so its audit trail
/// lives here as a lightweight append-only list of [StornoLogEntry]s.
///
/// A later iteration can promote this to a Drift table without changing the
/// public API — the Storno log screen watches `stornoLogProvider` directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Single audit record for a ticket cancellation performed via İPTAL.
class StornoLogEntry {
  /// Opaque identifier of the ticket that was voided. Empty for draft
  /// tickets that never hit the database.
  final String ticketId;

  /// Human-readable ticket number for the Storno log UI.
  final String orderNumber;

  /// Reason supplied by the waiter/cashier. Required and non-empty.
  final String reason;

  /// User id (from `currentUserProvider`) — `"unknown"` if none logged in.
  final String userId;

  /// Display name of the user who performed the cancellation.
  final String userName;

  /// Ticket grand total at the moment of cancellation, in cents.
  final int amountCents;

  /// Wall-clock timestamp of the cancellation.
  final DateTime timestamp;

  const StornoLogEntry({
    required this.ticketId,
    required this.orderNumber,
    required this.reason,
    required this.userId,
    required this.userName,
    required this.amountCents,
    required this.timestamp,
  });
}

/// Append-only in-memory list of [StornoLogEntry] records.
///
/// Newest entries are at index 0 — the log screen renders without sorting.
final stornoLogProvider =
    StateNotifierProvider<StornoLogNotifier, List<StornoLogEntry>>((ref) {
  return StornoLogNotifier();
});

class StornoLogNotifier extends StateNotifier<List<StornoLogEntry>> {
  StornoLogNotifier() : super(const []);

  /// Prepend a new entry to the log.
  void append(StornoLogEntry entry) {
    state = [entry, ...state];
  }

  /// Pilot-only escape hatch for tests — drops all entries.
  void clear() {
    state = const [];
  }
}
