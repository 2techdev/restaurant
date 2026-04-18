/// Top-level Riverpod providers for the Boss app.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_api/gastrocore_api.dart';

import 'boss_config.dart';

final apiBaseUrlProvider = Provider<String>(
  (ref) => BossConfig.defaultApiBaseUrl,
);

final tenantIdProvider = Provider<String>(
  (ref) => BossConfig.defaultTenantId,
);

final gastrocoreClientProvider = Provider<GastrocoreClient>((ref) {
  final client = GastrocoreClient(baseUrl: ref.watch(apiBaseUrlProvider));
  ref.onDispose(client.dispose);
  return client;
});
