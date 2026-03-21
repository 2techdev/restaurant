/// Embedded HTTP server for LAN sync — runs on the primary POS device.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'endpoints/menu_endpoint.dart';
import 'endpoints/orders_endpoint.dart';
import 'endpoints/sync_status_endpoint.dart';
import 'endpoints/tables_endpoint.dart';
import 'lan_sync_models.dart';
import 'sse_server.dart';

/// The embedded HTTP server that runs on the primary POS device.
///
/// Secondaries discover it via UDP beacon / mDNS, then:
///   1. POST /sync/handshake  — register and receive the SSE stream URL.
///   2. GET  /sync/events     — subscribe to real-time push updates (SSE).
///   3. GET  /orders          — pull orders since a cursor.
///   4. GET  /menu            — pull the full menu.
///   5. GET  /tables          — pull table states.
///   6. POST /orders          — push a new order from secondary.
///   7. POST /table-status    — push a table-status change from secondary.
class LanSyncService {
  LanSyncService({
    required this.deviceId,
    required this.deviceName,
    required this.tenantId,
    required this.ordersEndpoint,
    required this.menuEndpoint,
    required this.tablesEndpoint,
    required this.syncStatusEndpoint,
  });

  final String deviceId;
  final String deviceName;
  final String tenantId;

  final OrdersEndpoint ordersEndpoint;
  final MenuEndpoint menuEndpoint;
  final TablesEndpoint tablesEndpoint;
  final SyncStatusEndpoint syncStatusEndpoint;

  final SseServer _sseServer = SseServer();
  final Map<String, SyncPeer> _connectedPeers = {};

  HttpServer? _server;
  int? _port;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  bool get isRunning => _server != null;
  int? get port => _port;

  /// Connected secondaries — device ID → peer info.
  Map<String, SyncPeer> get connectedPeers => Map.unmodifiable(_connectedPeers);

  /// Number of active SSE subscribers.
  int get sseConnectionCount => _sseServer.connectionCount;

  /// Start the embedded server on a random available port.
  /// Returns the assigned port number.
  Future<int> start() async {
    if (isRunning) return _port!;

    final router = Router()
      // Health / handshake
      ..get('/sync/status', syncStatusEndpoint.getStatus)
      ..post('/sync/handshake', _handleHandshake)
      // SSE stream
      ..get('/sync/events', _sseServer.handler)
      // Orders
      ..get('/orders', ordersEndpoint.getOrders)
      ..post('/orders', ordersEndpoint.postOrder)
      // Menu
      ..get('/menu', menuEndpoint.getMenu)
      // Tables
      ..get('/tables', tablesEndpoint.getTables)
      ..post('/table-status', tablesEndpoint.postTableStatus);

    final handler = const Pipeline()
        .addMiddleware(_cors())
        .addMiddleware(logRequests())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
    _port = _server!.port;
    return _port!;
  }

  Future<void> stop() async {
    await _sseServer.closeAll();
    await _server?.close(force: true);
    _server = null;
    _port = null;
    _connectedPeers.clear();
  }

  // ---------------------------------------------------------------------------
  // Broadcast to secondaries
  // ---------------------------------------------------------------------------

  /// Push a [SyncMessage] to all connected secondary devices via SSE.
  void broadcast(SyncMessage message) {
    _sseServer.broadcast(message);
  }

  /// Push a named event (e.g. `'table_status'`) with an arbitrary payload.
  void broadcastTyped(String eventType, Map<String, dynamic> payload) {
    _sseServer.broadcastTyped(eventType, payload);
  }

  // ---------------------------------------------------------------------------
  // Handshake handler
  // ---------------------------------------------------------------------------

  Future<Response> _handleHandshake(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final req = HandshakeRequest.fromJson(json);

      // Determine the remote IP.
      final connInfo =
          request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
      final remoteIp = connInfo?.remoteAddress.address ?? 'unknown';

      _connectedPeers[req.deviceId] = SyncPeer(
        deviceId: req.deviceId,
        deviceName: req.deviceName,
        ipAddress: remoteIp,
        port: 0,
        role: DeviceRole.secondary,
        status: PeerConnectionStatus.connected,
        tenantId: req.tenantId,
        lastSeenAt: DateTime.now(),
      );

      final cursor = await syncStatusEndpoint.getCurrentCursor();
      final response = HandshakeResponse(
        primaryDeviceId: deviceId,
        primaryDeviceName: deviceName,
        tenantId: tenantId,
        syncCursor: cursor,
        vectorClock: VectorClock(),
        sseEndpoint: '/sync/events',
        acceptedAt: DateTime.now(),
      );

      return Response.ok(
        jsonEncode(response.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.badRequest(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  // ---------------------------------------------------------------------------
  // CORS middleware
  // ---------------------------------------------------------------------------

  static Middleware _cors() {
    const headers = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Accept',
    };
    return (Handler inner) => (Request req) async {
          if (req.method == 'OPTIONS') {
            return Response.ok('', headers: headers);
          }
          final res = await inner(req);
          return res.change(headers: headers);
        };
  }
}
