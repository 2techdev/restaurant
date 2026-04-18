/// Entry point for the GastroCore Kiosk application.
///
/// Shares the same database, domain layer, and providers as the POS app.
/// The kiosk flavor is customer-facing (no authentication) and uses a
/// large-screen, touch-optimised UI for self-ordering.
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
import 'package:gastrocore_pos/kiosk_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force landscape orientation for kiosk hardware (tablets / dedicated units).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Hide system bars for full-screen kiosk mode.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Shared database with the POS app (same SQLite file on device or dedicated
  // kiosk unit with its own file).
  final db = AppDatabase.create();
  await AppInitializer.initialize(db);

  final tenants = await db.select(db.tenants).get();
  final tenantId = tenants.first.id;

  // Pre-warm license cache.
  final licenseRepo = LicenseRepositoryImpl(db);
  await licenseRepo.getCurrentLicense(tenantId);

  // Stable device UUID — prefix with "K-" to distinguish kiosk devices.
  final prefs = await SharedPreferences.getInstance();
  var deviceId = prefs.getString('kiosk_device_id') ?? '';
  if (deviceId.isEmpty) {
    deviceId = 'K-${const Uuid().v4()}';
    await prefs.setString('kiosk_device_id', deviceId);
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
      child: const GastroCoreKioskApp(),
    ),
  );
}
