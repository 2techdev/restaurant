/// Sync entity configuration contract.
///
/// Each flavor declares a [SyncConfig] that describes:
///   - [pushEntities]  — table names this device generates and pushes to cloud.
///   - [pullEntities]  — table names this device consumes from the cloud.
///   - [deviceType]    — identifies this device in the sync hub.
///
/// The config is used by [SyncRepositoryImpl] and the server-side filter to
/// avoid sending irrelevant events to a device (e.g. the Kiosk does not need
/// shift data).
library;

/// Logical device role used by the sync hub.
enum SyncDeviceType { pos, kds, ods, kiosk, waiter }

/// Immutable configuration describing what a flavor syncs.
class SyncConfig {
  const SyncConfig({
    required this.deviceType,
    required this.pushEntities,
    required this.pullEntities,
  });

  final SyncDeviceType deviceType;

  /// Table names whose local changes are pushed to the cloud.
  final Set<String> pushEntities;

  /// Table names whose remote changes are applied locally.
  final Set<String> pullEntities;

  /// All entity types relevant to this flavor (union of push + pull).
  Set<String> get allEntities => {...pushEntities, ...pullEntities};
}
