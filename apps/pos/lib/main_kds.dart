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

  final syncUrl =
      prefs.getString('sync_server_url') ?? AppEndpoints.apiBaseUrl;
  final wsUrl = prefs.getString('ws_server_url') ?? AppEndpoints.wsBaseUrl;

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        tenantIdProvider.overrideWithValue(tenantId),
        deviceIdProvider.overrideWith((ref) => deviceId),
        syncServerUrlProvider.overrideWith((ref) => syncUrl),
        wsServerUrlProvider.overrideWith((ref) => wsUrl),
      ],
      child: const GastroCoreKdsApp(),
    ),
  );
}
