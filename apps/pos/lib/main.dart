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
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:gastrocore_pos/app.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/mypos/mypos_client.dart';
import 'package:gastrocore_pos/core/config/app_endpoints.dart';
import 'package:gastrocore_pos/core/data/app_initializer.dart';
import 'package:gastrocore_pos/core/data/seed_data.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/tenant/active_tenant_provider.dart';
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

    // Round-11 operator request: app-wide fullscreen — every screen
    // (login, PIN, POS shell, Bons history, Reports, Settings) must
    // run without the Android status bar / nav bar showing. The
    // POS shell-only immersive call from round-10 only kicked in once
    // the cashier was inside the till; intermediate routes still
    // surfaced the system chrome. Setting it here in `main` once at
    // startup, plus the native [`MainActivity.onWindowFocusChanged`]
    // re-applier, keeps the chrome hidden across the entire session.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: const [],
    );

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

  // Post-seed hard override. If any of the four "visible" tables is still
  // empty after the normal seed path ran — for instance because a silent
  // exception inside `_seed()` got swallowed somewhere upstream — force
  // a full re-seed so the pilot tablet never boots into an empty POS.
  //
  // `SeedData.seedForce()` calls `clearAll()` before inserting, so there
  // is no double-insert risk on the stable [kPilotTenantId] primary key.
  final tBoot = (await db.select(db.tenants).get()).length;
  final cBoot = (await db.select(db.categories).get()).length;
  final pBoot = (await db.select(db.products).get()).length;
  final tblBoot = (await db.select(db.restaurantTables).get()).length;
  debugPrint(
    '[BOOT] post-init counts tenants=$tBoot cats=$cBoot prods=$pBoot '
    'tables=$tblBoot',
  );
  if (tBoot == 0 || cBoot == 0 || pBoot == 0 || tblBoot == 0) {
    debugPrint('[BOOT] empty detected — forcing SeedData.seedForce()');
    await SeedData(db).seedForce();
  }

  // Resolve the active tenant ID.
  //
  // Pilot safeguard: hard-pin to [kPilotTenantId] instead of reading
  // `tenants.first.id`. The seed already writes this exact ID, and every
  // per-feature provider queries through `tenantIdProvider`, so forcing
  // the constant here makes drift architecturally impossible — no other
  // runtime path can slip a different UUID into the query scope. Accepted
  // as temporary for the single-tenant pilot; revisit if/when multi-
  // tenant boot is reintroduced.
  //
  // Log the row count so we can still see when the DB is empty.
  final tenants = await db.select(db.tenants).get();
  const tenantId = kPilotTenantId;
  debugPrint(
    '[BOOT] hard-pinned tenantId=$tenantId (tenants row count=${tenants.length})',
  );

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

  // Load the saved sync server URLs (fall back to the Hetzner pilot defaults
  // surfaced by AppEndpoints — override via Settings or `--dart-define`).
  final syncUrl =
      prefs.getString('sync_server_url') ?? AppEndpoints.apiBaseUrl;
  final wsUrl = prefs.getString('ws_server_url') ?? AppEndpoints.wsBaseUrl;

  // Hydrate the active tenant from SharedPreferences so a switcher choice
  // made in a previous session survives a process restart. Falls back to
  // the device's pinned primary tenant when no override is stored — pilot
  // devices stay single-tenant unless the operator opts into the
  // multiTenantSwitcherEnabled flag and picks a different tenant.
  final activeTenantNotifier = ActiveTenantNotifier(
    primaryTenantId: tenantId,
    prefs: prefs,
  );

  // Build the ProviderScope so we can restore brand auth before the first frame.
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      tenantIdProvider.overrideWithValue(tenantId),
      activeTenantProvider.overrideWith((ref) => activeTenantNotifier),
      deviceIdProvider.overrideWith((ref) => deviceId),
      syncServerUrlProvider.overrideWith((ref) => syncUrl),
      wsServerUrlProvider.overrideWith((ref) => wsUrl),
    ],
  );

  // Restore brand auth session (JWT token check + optional server refresh).
  // This sets isInitialized = true so the GoRouter redirect can decide the
  // initial route correctly on the very first frame.
  await container.read(brandAuthProvider.notifier).restoreSession();

  // Auto-warm the MyPOS terminal connection so the operator doesn't pay
  // the 1-3 s SDK handshake on their first ÖDE of the day. Fire-and-forget
  // — we never block startup on payment hardware, the heartbeat takes over
  // from there. Only runs when the operator actually has the MyPOS toggle
  // enabled in Settings; otherwise the call is skipped silently.
  unawaited(_warmMyPosConnection(prefs));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GastroCoreApp(),
    ),
  );
}

/// Reads `settings.v1.payment` straight from SharedPreferences (same key
/// the SettingsRepository uses) so we don't drag in the full Riverpod
/// graph just for a startup probe. If MyPOS is enabled, opens a one-shot
/// MyPosClient, calls `connect()` (fire-and-forget) and lets the plugin's
/// heartbeat + reconnect machinery keep the session warm from there.
Future<void> _warmMyPosConnection(SharedPreferences prefs) async {
  try {
    final raw = prefs.getString('settings.v1.payment');
    if (raw == null) return;
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) return;
    final mypos = json['mypos'];
    if (mypos is! Map<String, dynamic>) return;
    if (mypos['enabled'] != true) return;
    final ip = (mypos['ip'] as String?)?.trim() ?? '';
    final port = (mypos['port'] as int?) ?? 60180;
    if (ip.isEmpty) return;
    debugPrint('[BOOT] MyPOS auto-connect: $ip:$port');
    final client = MyPosClient.shared(terminalIp: ip, terminalPort: port);
    // Don't await — connection is async and the SDK heartbeat takes over.
    unawaited(client.connect());
  } catch (e) {
    debugPrint('[BOOT] MyPOS auto-connect skipped: $e');
  }
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
