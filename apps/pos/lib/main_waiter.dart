/// Entry point for the GastroCore Waiter application.
///
/// Shares the same database, domain layer, and providers as the POS app.
/// Only the root widget and router differ — the waiter app uses a
/// phone-optimised UI built for table-side ordering.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:gastrocore_pos/core/config/app_endpoints.dart';
import 'package:gastrocore_pos/core/data/app_initializer.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/licensing/data/repositories/license_repository_impl.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';
import 'package:gastrocore_pos/waiter_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Shared database with the POS app (same SQLite file on the same device,
  // or a separate device with its own file).
  final db = AppDatabase.create();
  await AppInitializer.initialize(db);

  final tenants = await db.select(db.tenants).get();
  final tenantId = tenants.first.id;

  // Pre-warm license cache.
  final licenseRepo = LicenseRepositoryImpl(db);
  await licenseRepo.getCurrentLicense(tenantId);

  // Stable device UUID — prefix with "W-" to distinguish waiter devices.
  final prefs = await SharedPreferences.getInstance();
  var deviceId = prefs.getString('waiter_device_id') ?? '';
  if (deviceId.isEmpty) {
    deviceId = 'W-${const Uuid().v4()}';
    await prefs.setString('waiter_device_id', deviceId);
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
      child: const GastroCoreWaiterApp(),
    ),
  );
}
