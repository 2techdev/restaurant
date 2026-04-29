/// Riverpod providers for the reports feature.
///
/// Exposes the repository plus a family of snapshot futures so the Z /
/// monthly / period tabs can each watch their own date window without
/// clobbering siblings. Seal actions go through a [StateNotifier] so the
/// UI can drive the button through idle / sealing / sealed states.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/reports/data/repositories/reports_repository.dart';
import 'package:gastrocore_pos/features/reports/domain/entities/report_entities.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ReportsRepository(db);
});

/// Immutable key for a [ReportSnapshot] request. Overriding `==` keeps
/// the FutureProvider.family cache stable across widget rebuilds so we
/// don't re-run the aggregate query on every frame.
class ReportWindow {
  const ReportWindow({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReportWindow &&
          other.from == from &&
          other.to == to);

  @override
  int get hashCode => Object.hash(from, to);
}

/// Aggregate snapshot for an arbitrary window. Used by the Z, monthly
/// and period tabs alike.
final reportSnapshotProvider =
    FutureProvider.family<ReportSnapshot, ReportWindow>((ref, window) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.generateSnapshot(
    tenantId: tenantId,
    from: window.from,
    to: window.to,
  );
});

/// Previously-sealed Z reports for the current tenant, newest first.
final zSealHistoryProvider = FutureProvider<List<ZSealEntity>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.listZSeals(tenantId);
});

enum ZSealState { idle, sealing, sealed, error }

class ZSealStatus {
  const ZSealStatus({
    required this.state,
    this.lastSeal,
    this.errorMessage,
  });

  final ZSealState state;
  final ZSealEntity? lastSeal;
  final String? errorMessage;

  static const idle = ZSealStatus(state: ZSealState.idle);
}

class ZSealNotifier extends StateNotifier<ZSealStatus> {
  ZSealNotifier(this._repo, this._tenantId, this._ref) : super(ZSealStatus.idle);

  final ReportsRepository _repo;
  final String _tenantId;
  final Ref _ref;

  Future<ZSealEntity?> seal({
    required String closedBy,
    required ReportSnapshot snapshot,
  }) async {
    state = const ZSealStatus(state: ZSealState.sealing);
    try {
      final seal = await _repo.sealZReport(
        tenantId: _tenantId,
        closedBy: closedBy,
        snapshot: snapshot,
      );
      state = ZSealStatus(state: ZSealState.sealed, lastSeal: seal);
      _ref.invalidate(zSealHistoryProvider);
      return seal;
    } catch (e) {
      state = ZSealStatus(state: ZSealState.error, errorMessage: e.toString());
      return null;
    }
  }

  void reset() {
    state = ZSealStatus.idle;
  }
}

final zSealNotifierProvider =
    StateNotifierProvider<ZSealNotifier, ZSealStatus>((ref) {
  final repo = ref.watch(reportsRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return ZSealNotifier(repo, tenantId, ref);
});
