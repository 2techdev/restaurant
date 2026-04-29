/// Entry point for the GastroCore Order Display Screen (ODS) application.
///
/// The ODS is a read-only, full-screen customer-facing display mounted on a
/// TV or monitor at the counter. It shows order numbers split into:
///   - "Preparing" — orders the kitchen is working on (amber)
///   - "Ready"     — orders ready for customer pickup (green, pulsing)
///
/// Shares the same Drift database and sync infrastructure as the POS,
/// Waiter, and Kiosk flavours. No local order creation occurs here.
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
import 'package:gastrocore_pos/features/ods/presentation/providers/ods_provider.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';
import 'package:gastrocore_pos/ods_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force landscape orientation — ODS is always shown on a wide screen.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Full-screen kiosk mode — hides system bars entirely.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final db = AppDatabase.create();
  await AppInitializer.initialize(db);

  final tenants = await db.select(db.tenants).get();
  final tenantId = tenants.first.id;

  // Pre-warm license cache.
  final licenseRepo = LicenseRepositoryImpl(db);
  await licenseRepo.getCurrentLicense(tenantId);

  // Stable device UUID — prefix with "ODS-" to distinguish display devices.
  final prefs = await SharedPreferences.getInstance();
  var deviceId = prefs.getString('ods_device_id') ?? '';
  if (deviceId.isEmpty) {
    deviceId = 'ODS-${const Uuid().v4()}';
    await prefs.setString('ods_device_id', deviceId);
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
      child: const _OdsBootstrap(),
    ),
  );
}

/// Bootstraps ODS-specific settings from SharedPreferences before rendering.
class _OdsBootstrap extends ConsumerWidget {
  const _OdsBootstrap();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rehydrate persisted ODS settings once on startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(odsSettingsPersistenceProvider).load();
    });

    return const GastroCoreOdsApp();
  }
}
