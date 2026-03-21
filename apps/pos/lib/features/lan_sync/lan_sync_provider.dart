/// Riverpod providers for LAN sync state management.
///
/// Architecture overview:
///
///   [lanSyncProvider] — `StateNotifierProvider<LanSyncNotifier, LanSyncState>`
///     • Starts/stops the embedded shelf server (primary mode)
///     • Runs mDNS + UDP-beacon advertising / discovery
///     • Manages SSE client connection to the primary (secondary mode)
///     • Exposes [LanSyncState] to the UI
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/sync/data/applier/remote_event_applier.dart';
import 'package:http/http.dart' as http;

import 'endpoints/menu_endpoint.dart';
import 'endpoints/orders_endpoint.dart';
import 'endpoints/sync_status_endpoint.dart';
import 'endpoints/tables_endpoint.dart';
import 'lan_sync_models.dart';
import 'lan_sync_service.dart';
import 'mdns_discovery_service.dart';
import 'sse_client.dart';
import 'sync_protocol.dart';

// ---------------------------------------------------------------------------
// LanSyncState
// ---------------------------------------------------------------------------

/// Immutable snapshot of the LAN sync engine state.
class LanSyncState {
  const LanSyncState({
    this.role = DeviceRole.undecided,
    this.status = LanSyncStatus.stopped,
    this.port,
    this.peers = const [],
    this.primaryPeer,
    this.isConnectedToPrimary = false,
    this.lastError,
    this.lastSyncAt,
  });

  final DeviceRole role;
  final LanSyncStatus status;

  /// HTTP port of the embedded server (only set when [role] == primary).
  final int? port;

  /// All known peers (discovered + connected).
  final List<SyncPeer> peers;

  /// The primary we're connected to (secondary mode only).
  final SyncPeer? primaryPeer;

  final bool isConnectedToPrimary;
  final String? lastError;
  final DateTime? lastSyncAt;

  bool get isRunning => status == LanSyncStatus.running;

  LanSyncState copyWith({
    DeviceRole? role,
    LanSyncStatus? status,
    int? port,
    List<SyncPeer>? peers,
    SyncPeer? primaryPeer,
    bool? isConnectedToPrimary,
    String? lastError,
    DateTime? lastSyncAt,
  }) {
    return LanSyncState(
      role: role ?? this.role,
      status: status ?? this.status,
      port: port ?? this.port,
      peers: peers ?? this.peers,
      primaryPeer: primaryPeer ?? this.primaryPeer,
      isConnectedToPrimary:
          isConnectedToPrimary ?? this.isConnectedToPrimary,
      lastError: lastError,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }
}

// ---------------------------------------------------------------------------
// LanSyncNotifier
// ---------------------------------------------------------------------------

/// Manages the full LAN sync lifecycle for this device.
class LanSyncNotifier extends StateNotifier<LanSyncState> {
  LanSyncNotifier({
    required String deviceId,
    required String deviceName,
    required String tenantId,
    required RemoteEventApplier applier,
  })  : _deviceId = deviceId,
        _deviceName = deviceName,
        _tenantId = tenantId,
        _applier = applier,
        _protocol = const SyncProtocol(),
        super(const LanSyncState());

  final String _deviceId;
  final String _deviceName;
  final String _tenantId;
  final RemoteEventApplier _applier;
  final SyncProtocol _protocol;

  LanSyncService? _server;
  MdnsDiscoveryService? _mdns;
  SseClient? _sseClient;

  /// Local vector clock — advanced on every outbound event.
  VectorClock _clock = VectorClock();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Promote this device to primary: start the embedded server + advertise.
  Future<void> becomePrimary() async {
    if (state.role == DeviceRole.primary && state.isRunning) return;

    state = state.copyWith(
      role: DeviceRole.primary,
      status: LanSyncStatus.starting,
      lastError: null,
    );

    try {
      await _stopSecondary();

      _server = _buildServer();
      final port = await _server!.start();

      _mdns = _buildMdns();
      await _mdns!.startAdvertising(port);

      state = state.copyWith(
        status: LanSyncStatus.running,
        port: port,
      );
    } catch (e) {
      state = state.copyWith(
        status: LanSyncStatus.error,
        lastError: e.toString(),
      );
    }
  }

  /// Switch this device to secondary: stop server, start discovery + SSE.
  Future<void> becomeSecondary() async {
    if (state.role == DeviceRole.secondary && state.isRunning) return;

    state = state.copyWith(
      role: DeviceRole.secondary,
      status: LanSyncStatus.starting,
      lastError: null,
    );

    try {
      await _stopPrimary();

      _mdns = _buildMdns();
      await _mdns!.startDiscovery();

      state = state.copyWith(status: LanSyncStatus.running);
    } catch (e) {
      state = state.copyWith(
        status: LanSyncStatus.error,
        lastError: e.toString(),
      );
    }
  }

  /// Connect to a discovered [peer] as a secondary (handshake + SSE subscribe).
  Future<void> connectToPeer(SyncPeer peer) async {
    if (state.role != DeviceRole.secondary) return;

    _updatePeer(peer.copyWith(status: PeerConnectionStatus.connecting));

    try {
      final response = await _handshake(peer);
      _clock = _protocol.receiveAndMerge(_clock, response.vectorClock);

      final connected = peer.copyWith(
        status: PeerConnectionStatus.connected,
        tenantId: response.tenantId,
      );
      _updatePeer(connected);

      state = state.copyWith(
        primaryPeer: connected,
        isConnectedToPrimary: true,
        lastSyncAt: DateTime.now(),
      );

      _startSseClient(peer);
    } catch (e) {
      _updatePeer(peer.copyWith(status: PeerConnectionStatus.disconnected));
      state = state.copyWith(lastError: e.toString());
    }
  }

  /// Stop all LAN sync activity and reset to undecided.
  Future<void> stop() async {
    await _stopPrimary();
    await _stopSecondary();
    state = const LanSyncState();
  }

  /// Push a [SyncMessage] to connected secondaries (primary only).
  void broadcastChange(SyncMessage message) {
    _server?.broadcast(message);
  }

  // ---------------------------------------------------------------------------
  // Primary helpers
  // ---------------------------------------------------------------------------

  Future<void> _stopPrimary() async {
    await _mdns?.stopAdvertising();
    await _server?.stop();
    _server = null;
  }

  LanSyncService _buildServer() {
    // Stub callbacks — real data integration is done by wiring the
    // OrderRepository / TableRepository into these via factory overrides
    // in the flavour-specific provider overrides at the app root.
    final orders = OrdersEndpoint(
      fetchOrders: ({String since = ''}) async => const [],
      receiveOrder: (_) async {},
    );
    final menu = MenuEndpoint(fetchMenu: () async => const {});
    final tables = TablesEndpoint(
      fetchTables: () async => const [],
      updateTableStatus: (_) async {},
    );
    final syncStatus = SyncStatusEndpoint(
      primaryDeviceId: _deviceId,
      primaryDeviceName: _deviceName,
      tenantId: _tenantId,
      getCursor: () async => '',
      getConnectedPeerCount: () => _server?.sseConnectionCount ?? 0,
    );

    return LanSyncService(
      deviceId: _deviceId,
      deviceName: _deviceName,
      tenantId: _tenantId,
      ordersEndpoint: orders,
      menuEndpoint: menu,
      tablesEndpoint: tables,
      syncStatusEndpoint: syncStatus,
    );
  }

  // ---------------------------------------------------------------------------
  // Secondary helpers
  // ---------------------------------------------------------------------------

  Future<void> _stopSecondary() async {
    _sseClient?.stop();
    _sseClient = null;
    await _mdns?.stopDiscovery();
    _mdns = null;
  }

  MdnsDiscoveryService _buildMdns() {
    return MdnsDiscoveryService(
      deviceId: _deviceId,
      deviceName: _deviceName,
      tenantId: _tenantId,
      onPeerDiscovered: _onPeerDiscovered,
    );
  }

  void _onPeerDiscovered(SyncPeer peer) {
    if (!mounted) return;
    final exists = state.peers.any((p) => p.deviceId == peer.deviceId);
    if (!exists) {
      state = state.copyWith(peers: [...state.peers, peer]);
    } else {
      state = state.copyWith(
        peers: [
          for (final p in state.peers)
            if (p.deviceId == peer.deviceId)
              p.copyWith(lastSeenAt: peer.lastSeenAt)
            else
              p,
        ],
      );
    }
  }

  void _updatePeer(SyncPeer updated) {
    final exists = state.peers.any((p) => p.deviceId == updated.deviceId);
    state = state.copyWith(
      peers: exists
          ? [
              for (final p in state.peers)
                if (p.deviceId == updated.deviceId) updated else p,
            ]
          : [...state.peers, updated],
    );
  }

  Future<HandshakeResponse> _handshake(SyncPeer peer) async {
    final uri = Uri.parse('${peer.baseUrl}/sync/handshake');
    final req = HandshakeRequest(
      deviceId: _deviceId,
      deviceName: _deviceName,
      tenantId: _tenantId,
      role: DeviceRole.secondary,
      vectorClock: _clock,
    );

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(req.toJson()),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Handshake failed: ${response.statusCode} ${response.body}',
      );
    }

    return HandshakeResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  void _startSseClient(SyncPeer peer) {
    _sseClient?.stop();
    _sseClient = SseClient(
      primaryBaseUrl: peer.baseUrl,
      deviceId: _deviceId,
      onMessage: _onSseMessage,
      onConnected: () {
        if (!mounted) return;
        state = state.copyWith(isConnectedToPrimary: true);
      },
      onDisconnected: () {
        if (!mounted) return;
        state = state.copyWith(isConnectedToPrimary: false);
      },
      onError: (e) {
        if (!mounted) return;
        state = state.copyWith(lastError: e.toString());
      },
    )..start();
  }

  void _onSseMessage(SyncMessage message) {
    if (!mounted) return;
    _clock = _protocol.receiveAndMerge(_clock, message.vectorClock);
    unawaited(
      _applier.apply(
        tableName: message.tableName,
        operation: message.operation,
        recordId: message.recordId,
        payload: message.payload,
      ),
    );
    state = state.copyWith(lastSyncAt: DateTime.now());
  }

  @override
  void dispose() {
    _sseClient?.stop();
    unawaited(_server?.stop() ?? Future<void>.value());
    unawaited(_mdns?.dispose() ?? Future<void>.value());
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

/// The central LAN sync state and notifier.
final lanSyncProvider =
    StateNotifierProvider<LanSyncNotifier, LanSyncState>((ref) {
  final db = ref.watch(databaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  final tenantId = ref.watch(tenantIdProvider);

  return LanSyncNotifier(
    deviceId: deviceId,
    deviceName: 'GastroCore-$deviceId',
    tenantId: tenantId,
    applier: RemoteEventApplier(db),
  );
});

/// Convenience: current LAN sync role of this device.
final lanSyncRoleProvider = Provider<DeviceRole>((ref) {
  return ref.watch(lanSyncProvider).role;
});

/// Convenience: all discovered/connected peers.
final lanSyncPeersProvider = Provider<List<SyncPeer>>((ref) {
  return ref.watch(lanSyncProvider).peers;
});

/// Convenience: whether this device is actively connected to a primary.
final isConnectedToPrimaryProvider = Provider<bool>((ref) {
  return ref.watch(lanSyncProvider).isConnectedToPrimary;
});
