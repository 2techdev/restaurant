/// Riverpod providers that bind the KDS app to the server's real-time hub.
///
/// The KDS screen shows a "LIVE" indicator driven by [kdsWsStateProvider] and
/// reacts to fresh [KdsEvent]s via [kdsLatestEventProvider]. Both are fed by a
/// single long-lived [KdsWsClient] that is disposed when the main screen
/// unmounts. Local Drift streams continue to render the ticket grid — the WS
/// feed is an out-of-band nudge so the kitchen knows the server pushed
/// something even before LAN sync has replicated it locally.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/kds_app/data/kds_ws_client.dart';
import 'package:gastrocore_pos/features/kds_app/presentation/providers/kds_providers.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';

/// Current connection state of the KDS realtime channel.
final kdsWsStateProvider =
    StateProvider<KdsWsState>((ref) => KdsWsState.disconnected);

/// Latest real-time event pushed from the server.
///
/// Widgets read this with `ref.listen` so they can pulse the LIVE dot or fire
/// a snack / beep without triggering a rebuild of the whole grid.
final kdsLatestEventProvider = StateProvider<KdsEvent?>((ref) => null);

/// Long-lived WebSocket client. `Provider` (not autoDispose) so the connection
/// stays open across transient screen rebuilds; it is torn down when the main
/// screen explicitly disposes its ProviderSubscription.
final kdsWsClientProvider = Provider<KdsWsClient>((ref) {
  final baseUrl = ref.watch(syncServerUrlProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final deviceId = ref.watch(deviceIdProvider);
  final station = ref.watch(kdsStationFilterProvider);

  final client = KdsWsClient(
    baseUrl: baseUrl,
    tenantId: tenantId,
    deviceId: deviceId,
    station: station,
    onEvent: (event) {
      ref.read(kdsLatestEventProvider.notifier).state = event;
    },
    onState: (state) {
      ref.read(kdsWsStateProvider.notifier).state = state;
    },
  );

  ref.onDispose(client.dispose);
  client.connect();
  return client;
});
