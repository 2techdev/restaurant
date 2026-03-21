/// LAN sync conflict resolution using vector clocks + last-write-wins.
library;

import 'lan_sync_models.dart';

/// Resolves concurrent edits from different POS devices.
///
/// Resolution strategy (applied in priority order):
///   1. **Causal ordering** — if vector clocks establish a happens-before
///      relationship, the later version wins unambiguously.
///   2. **DELETE dominance** — a delete always beats a concurrent update for
///      the same record (prevents zombie rows).
///   3. **Last-write-wins** — when edits are truly concurrent, the one with
///      the later [SyncMessage.createdAt] wall-clock timestamp wins.
class SyncProtocol {
  const SyncProtocol();

  // ---------------------------------------------------------------------------
  // Single-record conflict resolution
  // ---------------------------------------------------------------------------

  /// Resolve a conflict between [local] and [remote] edits of the same record.
  ///
  /// [local] and [remote] must share the same [SyncMessage.recordId].
  SyncConflict resolve(SyncMessage local, SyncMessage remote) {
    assert(
      local.recordId == remote.recordId,
      'resolve() called with mismatched recordIds: '
      '${local.recordId} vs ${remote.recordId}',
    );

    final cmp = local.vectorClock.compareTo(remote.vectorClock);

    // Causally ordered — no ambiguity.
    if (cmp > 0) {
      return _conflict(local, remote, local, ConflictResolution.localWins);
    }
    if (cmp < 0) {
      return _conflict(local, remote, remote, ConflictResolution.remoteWins);
    }

    // Concurrent edits — apply tiebreakers.

    // Delete dominates concurrent update.
    if (remote.operation == 'delete' && local.operation != 'delete') {
      return _conflict(local, remote, remote, ConflictResolution.remoteWins);
    }
    if (local.operation == 'delete' && remote.operation != 'delete') {
      return _conflict(local, remote, local, ConflictResolution.localWins);
    }

    // Last-write-wins by wall-clock timestamp.
    if (remote.createdAt.isAfter(local.createdAt)) {
      return _conflict(local, remote, remote, ConflictResolution.remoteWins);
    }
    return _conflict(local, remote, local, ConflictResolution.localWins);
  }

  // ---------------------------------------------------------------------------
  // Batch merge
  // ---------------------------------------------------------------------------

  /// Merge a batch of [incoming] messages against [localState].
  ///
  /// [localState] maps `recordId → SyncMessage` representing the device's
  /// current known version of each record.
  ///
  /// Returns the subset of messages that should be applied to the local
  /// database (i.e. remote wins or the record is new locally).
  List<SyncMessage> mergeIncoming({
    required List<SyncMessage> incoming,
    required Map<String, SyncMessage> localState,
  }) {
    final toApply = <SyncMessage>[];
    for (final msg in incoming) {
      final local = localState[msg.recordId];
      if (local == null) {
        // Record is new — always apply.
        toApply.add(msg);
      } else {
        final conflict = resolve(local, msg);
        if (conflict.resolution == ConflictResolution.remoteWins) {
          toApply.add(conflict.resolvedMessage);
        }
        // localWins → skip; local database is already correct.
      }
    }
    return toApply;
  }

  // ---------------------------------------------------------------------------
  // Clock management
  // ---------------------------------------------------------------------------

  /// Return a new clock advanced for [deviceId] sending a new event.
  ///
  /// Merges [current] with itself first (no-op) then increments [deviceId],
  /// so callers always get a strictly-monotone clock for this device.
  VectorClock advance(VectorClock current, String deviceId) {
    final next = current.copyWith();
    next.increment(deviceId);
    return next;
  }

  /// Merge the remote clock into [local] after receiving a message.
  ///
  /// This keeps the local clock up to date with the global causal history.
  VectorClock receiveAndMerge(VectorClock local, VectorClock remote) {
    return local.merge(remote);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static SyncConflict _conflict(
    SyncMessage local,
    SyncMessage remote,
    SyncMessage resolved,
    ConflictResolution resolution,
  ) {
    return SyncConflict(
      recordId: local.recordId,
      tableName: local.tableName,
      localMessage: local,
      remoteMessage: remote,
      resolvedMessage: resolved,
      resolution: resolution,
    );
  }
}
