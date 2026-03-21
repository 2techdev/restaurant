/// Data models for LAN peer-to-peer sync between GastroCore devices.
library;

import 'dart:convert';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Role of this device in the LAN sync mesh.
enum DeviceRole { primary, secondary, undecided }

/// Current state of the LAN sync engine on this device.
enum LanSyncStatus { stopped, starting, running, error }

/// Connection state of a peer.
enum PeerConnectionStatus { discovered, connecting, connected, disconnected }

/// How a sync conflict was resolved.
enum ConflictResolution { localWins, remoteWins }

// ---------------------------------------------------------------------------
// VectorClock
// ---------------------------------------------------------------------------

/// Lamport-style vector clock for causal ordering across devices.
///
/// Each entry maps a [deviceId] → logical counter. Used alongside wall-clock
/// timestamps for last-write-wins conflict resolution.
class VectorClock {
  VectorClock([Map<String, int>? initial])
      : _clock = Map<String, int>.from(initial ?? const {});

  final Map<String, int> _clock;

  Map<String, int> get entries => Map.unmodifiable(_clock);

  /// Increment this device's counter in-place.
  void increment(String deviceId) {
    _clock[deviceId] = (_clock[deviceId] ?? 0) + 1;
  }

  /// Return a new clock that is the element-wise max of [this] and [other].
  VectorClock merge(VectorClock other) {
    final merged = Map<String, int>.from(_clock);
    for (final entry in other._clock.entries) {
      final existing = merged[entry.key] ?? 0;
      if (entry.value > existing) merged[entry.key] = entry.value;
    }
    return VectorClock(merged);
  }

  /// Compare causally with [other].
  ///
  /// Returns:
  ///  * `1`  — this is strictly after [other]
  ///  * `-1` — this is strictly before [other]
  ///  * `0`  — concurrent (neither dominates)
  int compareTo(VectorClock other) {
    var thisAhead = false;
    var otherAhead = false;
    final allKeys = {..._clock.keys, ...other._clock.keys};
    for (final k in allKeys) {
      final mine = _clock[k] ?? 0;
      final theirs = other._clock[k] ?? 0;
      if (mine > theirs) thisAhead = true;
      if (theirs > mine) otherAhead = true;
    }
    if (thisAhead && !otherAhead) return 1;
    if (otherAhead && !thisAhead) return -1;
    return 0;
  }

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(_clock);

  factory VectorClock.fromJson(Map<String, dynamic> json) =>
      VectorClock(json.map((k, v) => MapEntry(k, (v as num).toInt())));

  VectorClock copyWith() => VectorClock(Map.from(_clock));

  @override
  String toString() => 'VectorClock($_clock)';

  @override
  bool operator ==(Object other) =>
      other is VectorClock && _mapsEqual(_clock, other._clock);

  @override
  int get hashCode => Object.hashAll(
        _clock.entries.map((e) => Object.hash(e.key, e.value)),
      );

  static bool _mapsEqual(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// SyncPeer
// ---------------------------------------------------------------------------

/// A discovered or connected peer device on the local network.
class SyncPeer {
  const SyncPeer({
    required this.deviceId,
    required this.deviceName,
    required this.ipAddress,
    required this.port,
    required this.role,
    required this.status,
    this.tenantId,
    this.lastSeenAt,
  });

  final String deviceId;
  final String deviceName;
  final String ipAddress;
  final int port;
  final DeviceRole role;
  final PeerConnectionStatus status;
  final String? tenantId;
  final DateTime? lastSeenAt;

  String get baseUrl => 'http://$ipAddress:$port';

  SyncPeer copyWith({
    String? deviceId,
    String? deviceName,
    String? ipAddress,
    int? port,
    DeviceRole? role,
    PeerConnectionStatus? status,
    String? tenantId,
    DateTime? lastSeenAt,
  }) {
    return SyncPeer(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      role: role ?? this.role,
      status: status ?? this.status,
      tenantId: tenantId ?? this.tenantId,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'ip_address': ipAddress,
        'port': port,
        'role': role.name,
        'tenant_id': tenantId,
      };

  factory SyncPeer.fromJson(Map<String, dynamic> json) => SyncPeer(
        deviceId: json['device_id'] as String,
        deviceName: json['device_name'] as String,
        ipAddress: json['ip_address'] as String,
        port: (json['port'] as num).toInt(),
        role: DeviceRole.values.byName(
          json['role'] as String? ?? 'undecided',
        ),
        status: PeerConnectionStatus.discovered,
        tenantId: json['tenant_id'] as String?,
      );
}

// ---------------------------------------------------------------------------
// SyncMessage
// ---------------------------------------------------------------------------

/// A single sync event exchanged between devices over LAN.
///
/// Compatible with [RemoteSyncEvent] used by the cloud sync to allow the same
/// [RemoteEventApplier] to process LAN events.
class SyncMessage {
  const SyncMessage({
    required this.id,
    required this.type,
    required this.deviceId,
    required this.tenantId,
    required this.tableName,
    required this.recordId,
    required this.operation,
    required this.payload,
    required this.vectorClock,
    required this.createdAt,
  });

  /// Event type: `'sync_event'`, `'heartbeat'`, or `'ack'`.
  final String type;
  final String id;
  final String deviceId;
  final String tenantId;
  final String tableName;
  final String recordId;

  /// Database operation: `'insert'`, `'update'`, or `'delete'`.
  final String operation;
  final Map<String, dynamic> payload;
  final VectorClock vectorClock;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'device_id': deviceId,
        'tenant_id': tenantId,
        'table_name': tableName,
        'record_id': recordId,
        'operation': operation,
        'payload': payload,
        'vector_clock': vectorClock.toJson(),
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory SyncMessage.fromJson(Map<String, dynamic> json) => SyncMessage(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'sync_event',
        deviceId: json['device_id'] as String,
        tenantId: json['tenant_id'] as String,
        tableName: json['table_name'] as String,
        recordId: json['record_id'] as String,
        operation: json['operation'] as String,
        payload: (json['payload'] as Map<String, dynamic>?) ?? {},
        vectorClock: VectorClock.fromJson(
          (json['vector_clock'] as Map<String, dynamic>?) ?? {},
        ),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now().toUtc(),
      );

  /// Encode as the `data:` line of an SSE event.
  String toSseData() => 'data: ${jsonEncode(toJson())}\n\n';
}

// ---------------------------------------------------------------------------
// SyncConflict
// ---------------------------------------------------------------------------

/// A detected conflict between local and remote versions of the same record.
class SyncConflict {
  const SyncConflict({
    required this.recordId,
    required this.tableName,
    required this.localMessage,
    required this.remoteMessage,
    required this.resolvedMessage,
    required this.resolution,
  });

  final String recordId;
  final String tableName;
  final SyncMessage localMessage;
  final SyncMessage remoteMessage;
  final SyncMessage resolvedMessage;
  final ConflictResolution resolution;
}

// ---------------------------------------------------------------------------
// Handshake
// ---------------------------------------------------------------------------

/// Sent by a secondary to register with a primary.
class HandshakeRequest {
  const HandshakeRequest({
    required this.deviceId,
    required this.deviceName,
    required this.tenantId,
    required this.role,
    required this.vectorClock,
    this.lastSyncCursor = '',
  });

  final String deviceId;
  final String deviceName;
  final String tenantId;
  final DeviceRole role;
  final VectorClock vectorClock;
  final String lastSyncCursor;

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'tenant_id': tenantId,
        'role': role.name,
        'vector_clock': vectorClock.toJson(),
        'last_sync_cursor': lastSyncCursor,
      };

  factory HandshakeRequest.fromJson(Map<String, dynamic> json) =>
      HandshakeRequest(
        deviceId: json['device_id'] as String,
        deviceName: json['device_name'] as String,
        tenantId: json['tenant_id'] as String,
        role: DeviceRole.values.byName(
          json['role'] as String? ?? 'secondary',
        ),
        vectorClock: VectorClock.fromJson(
          (json['vector_clock'] as Map<String, dynamic>?) ?? {},
        ),
        lastSyncCursor: json['last_sync_cursor'] as String? ?? '',
      );
}

/// Sent by the primary in response to a [HandshakeRequest].
class HandshakeResponse {
  const HandshakeResponse({
    required this.primaryDeviceId,
    required this.primaryDeviceName,
    required this.tenantId,
    required this.syncCursor,
    required this.vectorClock,
    required this.sseEndpoint,
    required this.acceptedAt,
  });

  final String primaryDeviceId;
  final String primaryDeviceName;
  final String tenantId;
  final String syncCursor;
  final VectorClock vectorClock;

  /// Relative path to the SSE stream, e.g. `'/sync/events'`.
  final String sseEndpoint;
  final DateTime acceptedAt;

  Map<String, dynamic> toJson() => {
        'primary_device_id': primaryDeviceId,
        'primary_device_name': primaryDeviceName,
        'tenant_id': tenantId,
        'sync_cursor': syncCursor,
        'vector_clock': vectorClock.toJson(),
        'sse_endpoint': sseEndpoint,
        'accepted_at': acceptedAt.toUtc().toIso8601String(),
      };

  factory HandshakeResponse.fromJson(Map<String, dynamic> json) =>
      HandshakeResponse(
        primaryDeviceId: json['primary_device_id'] as String,
        primaryDeviceName: json['primary_device_name'] as String,
        tenantId: json['tenant_id'] as String,
        syncCursor: json['sync_cursor'] as String? ?? '',
        vectorClock: VectorClock.fromJson(
          (json['vector_clock'] as Map<String, dynamic>?) ?? {},
        ),
        sseEndpoint: json['sse_endpoint'] as String? ?? '/sync/events',
        acceptedAt:
            DateTime.tryParse(json['accepted_at'] as String? ?? '') ??
                DateTime.now().toUtc(),
      );
}
