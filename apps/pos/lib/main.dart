/// Entry point for the GastroCore POS application.
///
/// Initialises Flutter bindings, creates the database, seeds demo data on
/// first launch, reads the tenant ID, and then starts the app wrapped in a
/// Riverpod [ProviderScope] with database and tenant overrides so all
/// providers share a single instance.
///
/// On startup the brand auth session is restored so the router can decide
/// whether to show the brand login screen or the staff PIN screen.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:gastrocore_pos/app.dart';
import 'package:gastrocore_pos/core/data/app_initializer.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/brand_auth/presentation/providers/brand_auth_provider.dart';
import 'package:gastrocore_pos/features/licensing/data/repositories/license_repository_impl.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';

void main() {
  // Global crash handler — catches both framework errors and any uncaught
  // async errors. We install this before bootstrap so a failure inside
  // initialize-the-database still ends up on the splash error screen
  // instead of a blank/black window on the pilot tablet.
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      if (kDebugMode) return;
      // In release we swallow framework-level errors so a single stray
      // assertion doesn't kill the tablet mid-service.
    };

    try {
      await _bootstrap();
    } catch (error, stack) {
      debugPrint('Startup failed: $error\n$stack');
      runApp(_StartupErrorApp(error: error, stack: stack));
    }
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

Future<void> _bootstrap() async {
  // Create the single database instance and run first-launch seed.
  final db = AppDatabase.create();
  await AppInitializer.initialize(db);

  // Read the tenant ID from the (now-seeded) database.
  final tenants = await db.select(db.tenants).get();
  final tenantId = tenants.first.id;

  // Pre-warm the license cache so the first frame knows the correct tier.
  final licenseRepo = LicenseRepositoryImpl(db);
  await licenseRepo.getCurrentLicense(tenantId);

  // Generate (or retrieve) a stable device UUID for cloud sync.
  final prefs = await SharedPreferences.getInstance();
  var deviceId = prefs.getString('device_id') ?? '';
  if (deviceId.isEmpty) {
    deviceId = const Uuid().v4();
    await prefs.setString('device_id', deviceId);
  }

  // Load the saved sync server URL (falls back to localhost default).
  final syncUrl =
      prefs.getString('sync_server_url') ?? 'http://localhost:8080';

  // Build the ProviderScope so we can restore brand auth before the first frame.
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      tenantIdProvider.overrideWithValue(tenantId),
      deviceIdProvider.overrideWith((ref) => deviceId),
      syncServerUrlProvider.overrideWith((ref) => syncUrl),
    ],
  );

  // Restore brand auth session (JWT token check + optional server refresh).
  // This sets isInitialized = true so the GoRouter redirect can decide the
  // initial route correctly on the very first frame.
  await container.read(brandAuthProvider.notifier).restoreSession();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GastroCoreApp(),
    ),
  );
}

/// Minimal fallback UI shown when [_bootstrap] throws.
///
/// Displays the exception and a "Tekrar dene" button that re-runs
/// bootstrap. Pilot staff can read the error and either retry or escalate.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error, required this.stack});

  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  'GastroCore başlatılamadı',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('Uygulama başlangıcında bir hata oluştu.'),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      '$error\n\n$stack',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: FilledButton.icon(
                    onPressed: () {
                      // Re-run bootstrap. Any exception lands back here.
                      _bootstrap().catchError((Object e, StackTrace s) {
                        runApp(_StartupErrorApp(error: e, stack: s));
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tekrar dene'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
