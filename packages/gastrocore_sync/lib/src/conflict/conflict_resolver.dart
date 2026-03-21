/// Conflict resolution strategies for offline-first sync.
library;

/// Outcome of conflict resolution.
enum ConflictOutcome {
  /// Local version was kept.
  keepLocal,

  /// Remote version was accepted.
  acceptRemote,

  /// Records were merged (custom merge logic).
  merged,
}

/// Result of resolving a conflict between local and remote records.
class ConflictResult<T> {
  final T resolved;
  final ConflictOutcome outcome;

  const ConflictResult({required this.resolved, required this.outcome});

  @override
  String toString() =>
      'ConflictResult(outcome: ${outcome.name})';
}

/// A record that can participate in conflict resolution.
abstract interface class Syncable {
  String get id;
  DateTime get updatedAt;

  /// True if this record was modified locally but not yet synced.
  bool get isDirty;
}

/// Strategy interface for resolving conflicts.
abstract interface class ConflictStrategy<T extends Syncable> {
  ConflictResult<T> resolve(T local, T remote);
}

/// Last-write-wins by [Syncable.updatedAt].
///
/// If timestamps are equal, the remote version wins (server is authority).
class LastWriteWinsStrategy<T extends Syncable>
    implements ConflictStrategy<T> {
  const LastWriteWinsStrategy();

  @override
  ConflictResult<T> resolve(T local, T remote) {
    if (local.updatedAt.isAfter(remote.updatedAt)) {
      return ConflictResult(
        resolved: local,
        outcome: ConflictOutcome.keepLocal,
      );
    }
    return ConflictResult(
      resolved: remote,
      outcome: ConflictOutcome.acceptRemote,
    );
  }
}

/// Always prefer the remote version (server-authoritative).
class RemoteWinsStrategy<T extends Syncable> implements ConflictStrategy<T> {
  const RemoteWinsStrategy();

  @override
  ConflictResult<T> resolve(T local, T remote) {
    return ConflictResult(
      resolved: remote,
      outcome: ConflictOutcome.acceptRemote,
    );
  }
}

/// Always prefer the local version (client-authoritative).
class LocalWinsStrategy<T extends Syncable> implements ConflictStrategy<T> {
  const LocalWinsStrategy();

  @override
  ConflictResult<T> resolve(T local, T remote) {
    return ConflictResult(
      resolved: local,
      outcome: ConflictOutcome.keepLocal,
    );
  }
}

/// Top-level resolver that dispatches to per-entity strategies.
///
/// Defaults to [LastWriteWinsStrategy] for any entity type not explicitly
/// registered.
class ConflictResolver {
  final Map<Type, ConflictStrategy<Syncable>> _strategies;

  ConflictResolver({
    Map<Type, ConflictStrategy<Syncable>>? strategies,
  }) : _strategies = strategies ?? {};

  void registerStrategy<T extends Syncable>(ConflictStrategy<T> strategy) {
    _strategies[T] = strategy as ConflictStrategy<Syncable>;
  }

  ConflictResult<T> resolve<T extends Syncable>(T local, T remote) {
    final strategy = (_strategies[T] ??
        const LastWriteWinsStrategy()) as ConflictStrategy<T>;
    return strategy.resolve(local, remote);
  }
}
