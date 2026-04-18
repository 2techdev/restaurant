/// Riverpod providers for the kitchen-stations feature.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/stations/data/station_repository.dart';
import 'package:gastrocore_pos/features/stations/domain/entities/station_entity.dart';

final stationRepositoryProvider = Provider<StationRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return StationRepository(db);
});

/// Streams the active stations for the current tenant (sorted).
final stationsProvider = StreamProvider<List<StationEntity>>((ref) {
  final repo = ref.watch(stationRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.watchActiveStations(tenantId);
});

/// All (incl. deactivated) stations — used by the settings editor.
final allStationsProvider = StreamProvider<List<StationEntity>>((ref) {
  final repo = ref.watch(stationRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.watchAllStations(tenantId);
});

/// `code → StationEntity` lookup for fast ticket/station joins.
final stationByCodeProvider = Provider<Map<String, StationEntity>>((ref) {
  final list = ref.watch(stationsProvider).valueOrNull ?? const [];
  return {for (final s in list) s.code: s};
});

/// Seeds Swiss default stations on first boot.
final stationSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.watch(stationRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  await repo.seedDefaults(tenantId);
});
