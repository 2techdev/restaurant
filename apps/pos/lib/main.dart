/// Entry point for the GastroCore POS application.
///
/// Initialises Flutter bindings, creates the database, seeds demo data on
/// first launch, reads the tenant ID, and then starts the app wrapped in a
/// Riverpod [ProviderScope] with database and tenant overrides so all
/// providers share a single instance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:gastrocore_pos/app.dart';
import 'package:gastrocore_pos/core/data/app_initializer.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/licensing/data/repositories/license_repository_impl.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Create the single database instance and run first-launch seed.
  final db = AppDatabase.create();
  await AppInitializer.initialize(db);

  // Read the tenant ID from the (now-seeded) database.
  final tenants = await db.select(db.tenants).get();
  final tenantId = tenants.first.id;

  // Pre-warm the license cache so the first frame knows the correct tier.
  // This is a read-only call — it never throws; falls back to FREE silently.
  final licenseRepo = LicenseRepositoryImpl(db);
  await licenseRepo.getCurrentLicense(tenantId);

  // Generate (or retrieve) a stable device UUID for cloud sync.
  // Stored in shared_preferences so it survives app restarts.
  final prefs = await SharedPreferences.getInstance();
  var deviceId = prefs.getString('device_id') ?? '';
  if (deviceId.isEmpty) {
    deviceId = const Uuid().v4();
    await prefs.setString('device_id', deviceId);
  }

  // Load the saved sync server URL (falls back to localhost default).
  final syncUrl =
      prefs.getString('sync_server_url') ?? 'http://localhost:8080';

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        tenantIdProvider.overrideWithValue(tenantId),
        deviceIdProvider.overrideWith((ref) => deviceId),
        syncServerUrlProvider.overrideWith((ref) => syncUrl),
      ],
      child: const GastroCoreApp(),
    ),
  );
}
