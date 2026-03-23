import 'package:drift/drift.dart';

/// Tracks other GastroCore POS devices discovered on the same LAN segment
/// for offline peer-to-peer sync.
///
/// Devices advertise themselves via mDNS/Bonjour and this table caches the
/// known peers so that sync can resume without re-discovery on every boot.
@DataClassName('LanSyncPeer')
class LanSyncPeers extends Table {
  /// Stable device identifier (UUID, set at first launch).
  TextColumn get deviceId => text()();

  /// Tenant this device belongs to.
  TextColumn get tenantId => text()();

  /// Human-readable device name (e.g. 'POS-Kasse-1').
  TextColumn get deviceName => text()();

  /// Last observed IPv4 or IPv6 address on the LAN.
  TextColumn get ipAddress => text()();

  /// TCP port the peer's sync HTTP server listens on.
  IntColumn get port => integer().withDefault(const Constant(7070))();

  /// GastroCore app version reported by the peer.
  TextColumn get appVersion => text().nullable()();

  /// Schema version the peer is running (used to detect incompatible peers).
  IntColumn get schemaVersion => integer().nullable()();

  /// Whether we currently consider this peer reachable.
  BoolColumn get isReachable =>
      boolean().withDefault(const Constant(false))();

  /// Last successful ping or sync with this peer.
  DateTimeColumn get lastSeenAt => dateTime().nullable()();

  /// When this peer record was first created.
  DateTimeColumn get createdAt => dateTime()();

  /// When this peer record was last updated.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {deviceId, tenantId};
}
