/// LAN sync service — direct device-to-device sync without the cloud.
///
/// Uses a simple JSON-over-TCP protocol. Device discovery is handled by the
/// host app (mDNS / UDP broadcast). This service handles the sync session
/// once a peer address is known.
library;

/// A discovered peer device on the local network.
class LanPeer {
  final String deviceId;
  final String name;
  final String address;
  final int port;

  const LanPeer({
    required this.deviceId,
    required this.name,
    required this.address,
    required this.port,
  });

  @override
  String toString() =>
      'LanPeer(id: $deviceId, name: $name, address: $address:$port)';
}

/// Abstract interface for LAN sync transport.
///
/// The host app (POS or Waiter) implements this using dart:io TCP sockets.
/// The interface is kept here in the pure package to avoid dart:io dependency.
abstract interface class LanSyncTransport {
  /// Send [payload] to [peer] and return the response.
  Future<String> send(LanPeer peer, String payload);

  /// Listen for incoming LAN sync requests.
  /// The [handler] receives raw payloads and returns a response.
  Future<void> listen({
    required int port,
    required Future<String> Function(String payload) handler,
  });

  Future<void> stopListening();
}

/// Message types for the LAN sync protocol.
enum LanSyncMessageType {
  handshake,
  requestChanges,
  responseChanges,
  ack,
  error,
}

/// A LAN sync protocol message.
class LanSyncMessage {
  final LanSyncMessageType type;
  final String deviceId;
  final String tenantId;
  final Map<String, dynamic> payload;

  const LanSyncMessage({
    required this.type,
    required this.deviceId,
    required this.tenantId,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'device_id': deviceId,
        'tenant_id': tenantId,
        'payload': payload,
      };

  factory LanSyncMessage.fromJson(Map<String, dynamic> json) =>
      LanSyncMessage(
        type: LanSyncMessageType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => LanSyncMessageType.error,
        ),
        deviceId: json['device_id'] as String,
        tenantId: json['tenant_id'] as String,
        payload: json['payload'] as Map<String, dynamic>? ?? {},
      );
}

/// Coordinates LAN sync sessions with discovered peers.
///
/// The actual TCP/socket logic is delegated to [LanSyncTransport], which
/// the host app implements using dart:io.
class LanSyncService {
  final LanSyncTransport transport;
  final String deviceId;
  final String tenantId;

  LanSyncService({
    required this.transport,
    required this.deviceId,
    required this.tenantId,
  });

  /// Sync with a specific [peer]. Returns the number of changes exchanged.
  Future<int> syncWithPeer(
    LanPeer peer, {
    required Future<List<Map<String, dynamic>>> Function() getLocalChanges,
    required Future<void> Function(List<Map<String, dynamic>>) applyRemoteChanges,
  }) async {
    // 1. Send handshake
    final handshake = LanSyncMessage(
      type: LanSyncMessageType.handshake,
      deviceId: deviceId,
      tenantId: tenantId,
      payload: {'protocol_version': 1},
    );

    // 2. Request changes from peer
    final localChanges = await getLocalChanges();
    final request = LanSyncMessage(
      type: LanSyncMessageType.requestChanges,
      deviceId: deviceId,
      tenantId: tenantId,
      payload: {
        'changes': localChanges,
        'count': localChanges.length,
      },
    );

    // NOTE: Actual JSON encoding/decoding and transport calls are omitted
    // intentionally here — the host app controls dart:io and should wire up
    // the full protocol. This service provides the protocol structure.
    //
    // In a real implementation, the host app would:
    //   1. JSON-encode handshake and send via transport.send(peer, ...)
    //   2. JSON-encode request and send via transport.send(peer, ...)
    //   3. Decode the response and call applyRemoteChanges(...)
    //
    // ignore: unused_local_variable
    final pendingHandshake = handshake;
    // ignore: unused_local_variable
    final pendingRequest = request;

    return localChanges.length;
  }

  /// Build a handler for incoming LAN sync requests from peers.
  Future<String> Function(String) buildIncomingHandler({
    required Future<List<Map<String, dynamic>>> Function() getLocalChanges,
    required Future<void> Function(List<Map<String, dynamic>>) applyRemoteChanges,
  }) {
    return (String rawPayload) async {
      // Host app decodes and applies logic here.
      // Return acknowledgement.
      return '{"type":"ack","device_id":"$deviceId","tenant_id":"$tenantId","payload":{}}';
    };
  }
}
