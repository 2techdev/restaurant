/// Outbox pattern implementation — pushes pending events to the cloud.
library;

import 'package:gastrocore_api/gastrocore_api.dart';
import 'package:gastrocore_models/gastrocore_models.dart';

import 'outbox_repository.dart';

/// Result of a flush operation.
class OutboxFlushResult {
  final int pushed;
  final int failed;
  final List<String> errors;

  const OutboxFlushResult({
    required this.pushed,
    required this.failed,
    this.errors = const [],
  });

  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() =>
      'OutboxFlushResult(pushed: $pushed, failed: $failed)';
}

/// Reads pending [SyncEventEntity] records from the outbox and pushes them
/// to the cloud API in batches.
class OutboxService {
  final OutboxRepository repository;
  final GastrocoreClient apiClient;
  final String tenantId;

  /// Maximum events per API call.
  final int batchSize;

  /// Maximum retry attempts before giving up on an event.
  final int maxRetries;

  OutboxService({
    required this.repository,
    required this.apiClient,
    required this.tenantId,
    this.batchSize = 50,
    this.maxRetries = 3,
  });

  bool _flushing = false;

  /// Push all pending outbox events to the server.
  ///
  /// Idempotent — safe to call multiple times concurrently (only one flush
  /// runs at a time).
  Future<OutboxFlushResult> flush() async {
    if (_flushing) return const OutboxFlushResult(pushed: 0, failed: 0);
    _flushing = true;

    int totalPushed = 0;
    int totalFailed = 0;
    final errors = <String>[];

    try {
      while (true) {
        final events = await repository.getPendingEvents(
          maxRetries: maxRetries,
        );

        if (events.isEmpty) break;

        final batch = events.take(batchSize).toList();

        for (final event in batch) {
          await repository.markUploading(event.id);
        }

        try {
          final response = await apiClient.sync.pushEvents(
            tenantId: tenantId,
            events: batch,
          );

          final now = DateTime.now();
          for (final event in batch) {
            if (!response.rejectedIds.contains(event.recordId)) {
              await repository.markUploaded(event.id, now);
              totalPushed++;
            } else {
              await repository.markFailed(
                event.id,
                'Rejected by server',
              );
              totalFailed++;
              errors.add('Event ${event.id} rejected by server');
            }
          }
        } on ApiException catch (e) {
          for (final event in batch) {
            await repository.markFailed(event.id, e.toString());
          }
          totalFailed += batch.length;
          errors.add(e.toString());
          break; // Stop flushing on API error
        }

        if (batch.length < batchSize) break;
      }
    } finally {
      _flushing = false;
    }

    return OutboxFlushResult(
      pushed: totalPushed,
      failed: totalFailed,
      errors: errors,
    );
  }
}
