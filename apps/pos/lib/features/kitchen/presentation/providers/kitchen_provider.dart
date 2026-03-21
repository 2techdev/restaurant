/// Riverpod providers for the Kitchen Display System (KDS).
///
/// Exposes the [KitchenRepositoryImpl] singleton and reactive streams
/// for active tickets and completed-today count.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/kitchen/data/repositories/kitchen_repository_impl.dart';
import 'package:gastrocore_pos/features/kitchen/domain/entities/kitchen_ticket_entity.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// Singleton [KitchenRepositoryImpl] backed by the app database.
final kitchenRepositoryProvider = Provider<KitchenRepositoryImpl>((ref) {
  final db = ref.watch(databaseProvider);
  return KitchenRepositoryImpl(db);
});

// ---------------------------------------------------------------------------
// Active tickets stream
// ---------------------------------------------------------------------------

/// Stream of kitchen tickets with status 'pending' or 'preparing'.
///
/// The KDS screen watches this provider; the UI rebuilds whenever a new
/// ticket is created or an existing one is bumped.
final activeKitchenTicketsProvider =
    StreamProvider<List<KitchenTicketEntity>>((ref) {
  final repo = ref.watch(kitchenRepositoryProvider);
  return repo.watchActiveTickets();
});

// ---------------------------------------------------------------------------
// Completed-today count
// ---------------------------------------------------------------------------

/// Number of kitchen tickets completed (bumped) today.
///
/// Displayed in the KDS stats bar as "READY" count.
final completedTodayProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(kitchenRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.watchCompletedTodayCount(tenantId);
});
