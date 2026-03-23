/// Riverpod providers for the Gang ordering feature.
///
/// Exposes gang templates (for display / selection) and the gang
/// seeding logic that runs once on tenant init.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/gang/data/gang_repository.dart';
import 'package:gastrocore_pos/features/gang/domain/entities/gang_template_entity.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final gangRepositoryProvider = Provider<GangRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return GangRepository(db);
});

// ---------------------------------------------------------------------------
// Gang templates list (watched)
// ---------------------------------------------------------------------------

/// Streams the active gang templates for the current tenant, sorted by
/// sortOrder. Used by POS gang selector and KDS gang grouping.
final gangTemplatesProvider =
    StreamProvider<List<GangTemplateEntity>>((ref) {
  final repo = ref.watch(gangRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.watchGangTemplates(tenantId);
});

/// A map of gangId → GangTemplateEntity for fast lookups.
final gangTemplateMapProvider =
    Provider<Map<String, GangTemplateEntity>>((ref) {
  final templates = ref.watch(gangTemplatesProvider).valueOrNull ?? [];
  return {for (final t in templates) t.id: t};
});

// ---------------------------------------------------------------------------
// Seed notifier
// ---------------------------------------------------------------------------

/// Seeds the default Swiss Gangs for the current tenant if none exist.
/// Called once from main.dart after the DB is ready.
final gangSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.watch(gangRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  await repo.seedDefaultGangs(tenantId);
});
