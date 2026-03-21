/// mDNS service registration (primary) and discovery (secondary).
///
/// Two complementary strategies are used in parallel:
///
/// **Primary (advertising)**
///   Broadcasts a small JSON beacon over UDP multicast every 5 seconds.
///   The beacon contains the HTTP server port so secondaries can connect.
///
/// **Secondary (discovery)**
///   1. Listens on the same UDP multicast group for beacons.
///   2. Additionally runs periodic mDNS PTR-record queries via [MDnsClient]
///      so the system works even when the primary is already running and its
///      one-time beacon was missed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import 'lan_sync_models.dart';

/// mDNS service-type label used for GastroCore LAN sync.
const kGastroCoreServiceType = '_gastrocore._tcp.local';

/// Fixed UDP port on which beacons are broadcast.
const kGastroCoreBeaconPort = 52374;

/// The IPv4 mDNS multicast group address.
const _kMdnsMulticastGroup = '224.0.0.251';

/// Handles mDNS-based service announcement (primary) and discovery (secondary).
class MdnsDiscoveryService {
  MdnsDiscoveryService({
    required this.deviceId,
    required this.deviceName,
    required this.tenantId,
    required this.onPeerDiscovered,
  });

  final String deviceId;
  final String deviceName;
  final String tenantId;

  /// Called each time a new primary is discovered (or a known one is refreshed).
  final void Function(SyncPeer peer) onPeerDiscovered;

  // Primary (advertising) state.
  RawDatagramSocket? _beaconSocket;
  Timer? _beaconTimer;
  bool _advertising = false;

  // Secondary (discovery) state.
  RawDatagramSocket? _listenerSocket;
  MDnsClient? _mdnsClient;
  Timer? _mdnsScanTimer;
  bool _scanning = false;

  // ---------------------------------------------------------------------------
  // Primary — advertise
  // ---------------------------------------------------------------------------

  /// Start advertising this device as a LAN sync primary on [httpPort].
  Future<void> startAdvertising(int httpPort) async {
    if (_advertising) return;
    _advertising = true;

    try {
      _beaconSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
    } catch (_) {
      // Some Android builds deny DGRAM sockets — continue without beacons.
      _beaconSocket = null;
    }

    // Broadcast immediately then on interval.
    _sendBeacon(httpPort);
    _beaconTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _sendBeacon(httpPort));
  }

  void _sendBeacon(int httpPort) {
    if (_beaconSocket == null) return;
    final payload = jsonEncode({
      'device_id': deviceId,
      'device_name': deviceName,
      'tenant_id': tenantId,
      'port': httpPort,
      'role': 'primary',
      'service': kGastroCoreServiceType,
    });
    try {
      _beaconSocket!.send(
        utf8.encode(payload),
        InternetAddress(_kMdnsMulticastGroup),
        kGastroCoreBeaconPort,
      );
    } catch (_) {
      // Network temporarily unavailable — next timer tick will retry.
    }
  }

  Future<void> stopAdvertising() async {
    _advertising = false;
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _beaconSocket?.close();
    _beaconSocket = null;
  }

  // ---------------------------------------------------------------------------
  // Secondary — discover
  // ---------------------------------------------------------------------------

  /// Start listening for primary devices on the LAN.
  Future<void> startDiscovery() async {
    if (_scanning) return;
    _scanning = true;

    // Strategy 1: UDP multicast beacon listener.
    await _bindBeaconListener();

    // Strategy 2: periodic mDNS PTR query.
    _runMdnsQuery();
    _mdnsScanTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _runMdnsQuery());
  }

  Future<void> _bindBeaconListener() async {
    try {
      _listenerSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kGastroCoreBeaconPort,
        reuseAddress: true,
      );
      _listenerSocket!.joinMulticast(InternetAddress(_kMdnsMulticastGroup));
      _listenerSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _listenerSocket?.receive();
        if (dg == null) return;
        _processBeacon(dg.data, dg.address.address);
      });
    } catch (_) {
      // Port may be in use (e.g. primary is on same device during testing).
      _listenerSocket = null;
    }
  }

  void _processBeacon(List<int> data, String senderIp) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      final beaconId = json['device_id'] as String? ?? '';
      if (beaconId == deviceId) return; // ignore self-beacons

      final peer = SyncPeer(
        deviceId: beaconId,
        deviceName: json['device_name'] as String? ?? 'Unknown',
        ipAddress: senderIp,
        port: (json['port'] as num?)?.toInt() ?? 80,
        role: DeviceRole.primary,
        status: PeerConnectionStatus.discovered,
        tenantId: json['tenant_id'] as String?,
        lastSeenAt: DateTime.now(),
      );
      onPeerDiscovered(peer);
    } catch (_) {
      // Malformed beacon — ignore.
    }
  }

  Future<void> _runMdnsQuery() async {
    if (!_scanning) return;
    try {
      _mdnsClient ??= MDnsClient();
      await _mdnsClient!.start();

      await for (final ptr in _mdnsClient!.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(kGastroCoreServiceType),
        timeout: const Duration(seconds: 5),
      )) {
        await for (final srv in _mdnsClient!.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
          timeout: const Duration(seconds: 5),
        )) {
          await for (final ip in _mdnsClient!.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: const Duration(seconds: 5),
          )) {
            final peer = SyncPeer(
              deviceId: ptr.domainName,
              deviceName: srv.target,
              ipAddress: ip.address.address,
              port: srv.port,
              role: DeviceRole.primary,
              status: PeerConnectionStatus.discovered,
              tenantId: null,
              lastSeenAt: DateTime.now(),
            );
            onPeerDiscovered(peer);
          }
        }
      }
    } catch (_) {
      // mDNS queries may fail on restricted networks — UDP beacons are the
      // primary fallback and do not depend on mDNS.
    }
  }

  Future<void> stopDiscovery() async {
    _scanning = false;
    _mdnsScanTimer?.cancel();
    _mdnsScanTimer = null;
    _listenerSocket?.close();
    _listenerSocket = null;
    _mdnsClient?.stop();
    _mdnsClient = null;
  }

  Future<void> dispose() async {
    await stopAdvertising();
    await stopDiscovery();
  }
}
