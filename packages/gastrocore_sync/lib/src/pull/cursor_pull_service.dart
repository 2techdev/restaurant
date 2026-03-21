/// Cursor-based pull sync — fetches incremental changes from the cloud.
library;

import 'package:gastrocore_api/gastrocore_api.dart';

/// Persists the sync cursor between sessions.
abstract interface class SyncCursorStore {
  Future<String> getCursor(String tenantId);
  Future<void> saveCursor(String tenantId, String cursor);
}

/// Applies incoming change records to local storage.
abstract interface class ChangeApplier {
  /// Apply a list of change records (as raw JSON maps) to local storage.
  /// Implementations should handle insert / update / delete operations.
  Future<void> apply(List<Map<String, dynamic>> changes);
}

/// Result of a pull operation.
class PullResult {
  final int changesApplied;
  final String cursor;
  final bool hadMore;

  const PullResult({
    required this.changesApplied,
    required this.cursor,
    this.hadMore = false,
  });

  @override
  String toString() =>
      'PullResult(applied: $changesApplied, hadMore: $hadMore)';
}

/// Pulls incremental changes from the cloud using cursor-based pagination.
///
/// Consumers must supply a [SyncCursorStore] (to persist the cursor across
/// app restarts) and a [ChangeApplier] (to write changes to local storage).
class CursorPullService {
  final GastrocoreClient apiClient;
  final SyncCursorStore cursorStore;
  final ChangeApplier applier;

  /// Maximum records per pull request.
  final int pageSize;

  CursorPullService({
    required this.apiClient,
    required this.cursorStore,
    required this.applier,
    this.pageSize = 100,
  });

  /// Pull all available changes for [tenantId].
  ///
  /// Continues fetching pages until [PullResponse.hasMore] is false.
  Future<PullResult> pull(String tenantId) async {
    var cursor = await cursorStore.getCursor(tenantId);
    int totalApplied = 0;
    bool hadMore = false;

    while (true) {
      final response = await apiClient.sync.pullChanges(
        tenantId: tenantId,
        cursor: cursor,
        limit: pageSize,
      );

      if (response.changes.isNotEmpty) {
        await applier.apply(response.changes);
        totalApplied += response.changes.length;
      }

      cursor = response.nextCursor;
      await cursorStore.saveCursor(tenantId, cursor);

      if (!response.hasMore) break;
      hadMore = true;
    }

    return PullResult(
      changesApplied: totalApplied,
      cursor: cursor,
      hadMore: hadMore,
    );
  }
}
