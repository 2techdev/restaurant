/// Entry point for the GastroCore KDS (Kitchen Display System) application.
///
/// Shares the same database, domain layer, and providers as the POS app.
/// The KDS flavor is kitchen-facing — full-screen immersive mode, large
/// ticket grid, and auto-refresh via the Drift reactive stream.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:gastrocore_pos/core/config/app_endpoints.dart';
import 'package:gastrocore_pos/core/data/app_initializer.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/network/network_locator.dart';
import 'package:gastrocore_pos/core/network/network_locator_provider.dart';
import 'package:gastrocore_pos/features/licensing/data/repositories/license_repository_impl.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';
import 'package:gastrocore_pos/kds_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force landscape orientation — KDS is always wall-mounted in landscape.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Full-screen immersive mode — hides system bars for kitchen display.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Shared database with the POS app (same SQLite file or separate device).
  final db = AppDatabase.create();
  await AppInitializer.initialize(db);

  final tenants = await db.select(db.tenants).get();
  final tenantId = tenants.first.id;

  // Pre-warm license cache.
  final licenseRepo = LicenseRepositoryImpl(db);
  await licenseRepo.getCurrentLicense(tenantId);

  // Stable device UUID — prefix with "KDS-" to distinguish kitchen displays.
  final prefs = await SharedPreferences.getInstance();
  var deviceId = prefs.getString('kds_device_id') ?? '';
  if (deviceId.isEmpty) {
    deviceId = 'KDS-${const Uuid().v4()}';
    await prefs.setString('kds_device_id', deviceId);
  }

  // LAN-first endpoint resolution (see main_waiter.dart for the rationale).
  // KDS particularly benefits because kitchen → POS ticket-pull traffic
  // is high-frequency and entirely intra-restaurant; routing it through
  // Hetzner is unnecessary cost + latency.
  final locator = NetworkLocator();
  final resolved = await locator.resolve();
  locator.startDailyReprobe();

  final syncUrl = prefs.getString('sync_server_url') ?? resolved.apiBaseUrl;
  final wsUrl = prefs.getString('ws_server_url') ?? resolved.wsBaseUrl;
  // Cloud safety net (kept for symmetry with main_waiter / future logging).
  // ignore: unused_local_variable
  final cloudFallbackApi = AppEndpoints.apiBaseUrl;

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        tenantIdProvider.overrideWithValue(tenantId),
        deviceIdProvider.overrideWith((ref) => deviceId),
        networkLocatorProvider.overrideWithValue(locator),
        syncServerUrlProvider.overrideWith((ref) => syncUrl),
        wsServerUrlProvider.overrideWith((ref) => wsUrl),
      ],
      child: const GastroCoreKdsApp(),
    ),
  );
}
