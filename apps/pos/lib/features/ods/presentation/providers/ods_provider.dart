/// Riverpod providers for the Order Display Screen (ODS).
///
/// The ODS is read-only: it watches the local Drift database for ticket status
/// changes and partitions orders into "Preparing" and "Ready" buckets.
/// Ready orders are auto-removed after [autoRemoveTimeout] (default 5 min).
library;

import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';

// ---------------------------------------------------------------------------
// Settings providers (persisted in SharedPreferences)
// ---------------------------------------------------------------------------

/// Restaurant name displayed at the top of the ODS screen.
final odsRestaurantNameProvider = StateProvider<String>(
  (ref) => 'GastroCore',
);

/// Whether the chime sound is enabled when orders become ready.
final odsSoundEnabledProvider = StateProvider<bool>((ref) => true);

/// Minutes before a "Ready" order is automatically removed from the display.
final odsAutoRemoveMinutesProvider = StateProvider<int>((ref) => 5);

/// Persists ODS settings to SharedPreferences and rehydrates on startup.
final odsSettingsPersistenceProvider = Provider<OdsSettingsPersistence>((ref) {
  return OdsSettingsPersistence(ref);
});

class OdsSettingsPersistence {
  OdsSettingsPersistence(this._ref);

  final Ref _ref;

  static const _keyRestaurantName = 'ods_restaurant_name';
  static const _keySoundEnabled = 'ods_sound_enabled';
  static const _keyAutoRemoveMinutes = 'ods_auto_remove_minutes';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyRestaurantName);
    if (name != null) _ref.read(odsRestaurantNameProvider.notifier).state = name;
    final sound = prefs.getBool(_keySoundEnabled);
    if (sound != null) _ref.read(odsSoundEnabledProvider.notifier).state = sound;
    final minutes = prefs.getInt(_keyAutoRemoveMinutes);
    if (minutes != null) {
      _ref.read(odsAutoRemoveMinutesProvider.notifier).state = minutes;
    }
  }

  Future<void> saveRestaurantName(String name) async {
    _ref.read(odsRestaurantNameProvider.notifier).state = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRestaurantName, name);
  }

  Future<void> saveSoundEnabled(bool enabled) async {
    _ref.read(odsSoundEnabledProvider.notifier).state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySoundEnabled, enabled);
  }

  Future<void> saveAutoRemoveMinutes(int minutes) async {
    _ref.read(odsAutoRemoveMinutesProvider.notifier).state = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAutoRemoveMinutes, minutes);
  }
}

// ---------------------------------------------------------------------------
// Order model
// ---------------------------------------------------------------------------

/// An order entry shown on the ODS display.
class OdsOrder {
  const OdsOrder({
    required this.id,
    required this.orderNumber,
    required this.channel,
    required this.status,
    required this.updatedAt,
    this.readyAt,
  });

  final String id;
  final int orderNumber;

  /// Source channel: pos, waiter, kiosk, qr, web.
  final String channel;

  /// ODS-level status: 'preparing' | 'ready'.
  final String status;

  final DateTime updatedAt;

  /// When the order transitioned to "ready" (for auto-remove countdown).
  final DateTime? readyAt;

  String get formattedNumber =>
      '#${orderNumber.toString().padLeft(3, '0')}';

  bool get isPreparing => status == 'preparing';
  bool get isReady => status == 'ready';

  OdsOrder copyWith({DateTime? readyAt}) => OdsOrder(
        id: id,
        orderNumber: orderNumber,
        channel: channel,
        status: status,
        updatedAt: updatedAt,
        readyAt: readyAt ?? this.readyAt,
      );
}

// ---------------------------------------------------------------------------
// Ticket status helpers
// ---------------------------------------------------------------------------

/// Ticket statuses that map to "Preparing" on the ODS.
const _preparingStatuses = {
  'items_added',
  'sent_to_kitchen',
};

/// Ticket statuses that map to "Ready" on the ODS.
const _readyStatuses = {
  'partially_served',
  'fully_served',
  'bill_requested',
};

// ---------------------------------------------------------------------------
// ODS State
// ---------------------------------------------------------------------------

class OdsState {
  const OdsState({
    this.preparing = const [],
    this.ready = const [],
    this.isConnected = false,
  });

  final List<OdsOrder> preparing;
  final List<OdsOrder> ready;
  final bool isConnected;

  OdsState copyWith({
    List<OdsOrder>? preparing,
    List<OdsOrder>? ready,
    bool? isConnected,
  }) {
    return OdsState(
      preparing: preparing ?? this.preparing,
      ready: ready ?? this.ready,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

// ---------------------------------------------------------------------------
// ODS Notifier
// ---------------------------------------------------------------------------

class OdsNotifier extends StateNotifier<OdsState> {
  OdsNotifier({
    required AppDatabase db,
    required String tenantId,
    required Ref ref,
  })  : _db = db,
        _tenantId = tenantId,
        _ref = ref,
        super(const OdsState()) {
    _subscribe();
    _startAutoRemoveTimer();
  }

  final AppDatabase _db;
  final String _tenantId;
  final Ref _ref;
  StreamSubscription<List<Ticket>>? _ticketSub;
  Timer? _autoRemoveTimer;
  Set<String> _previousReadyIds = {};

  void _subscribe() {
    final query = _db.select(_db.tickets)
      ..where(
        (t) =>
            t.tenantId.equals(_tenantId) &
            t.isDeleted.equals(false) &
            t.status.isIn([..._preparingStatuses, ..._readyStatuses]),
      )
      ..orderBy([(t) => drift.OrderingTerm.asc(t.orderNumber)]);

    _ticketSub = query.watch().listen(_onTickets);
  }

  void _onTickets(List<Ticket> tickets) {
    final preparing = <OdsOrder>[];
    final ready = <OdsOrder>[];
    final now = DateTime.now();

    final autoRemoveMinutes = _ref.read(odsAutoRemoveMinutesProvider);

    for (final t in tickets) {
      if (_preparingStatuses.contains(t.status)) {
        preparing.add(OdsOrder(
          id: t.id,
          orderNumber: t.orderNumber,
          channel: t.channel,
          status: 'preparing',
          updatedAt: t.updatedAt,
        ));
      } else if (_readyStatuses.contains(t.status)) {
        // Preserve existing readyAt if already tracked; set now for new entries.
        final existingReadyAt = state.ready
            .where((o) => o.id == t.id)
            .map((o) => o.readyAt)
            .firstOrNull;

        final readyAt = existingReadyAt ?? now;
        final age = now.difference(readyAt);

        if (age.inMinutes < autoRemoveMinutes) {
          ready.add(OdsOrder(
            id: t.id,
            orderNumber: t.orderNumber,
            channel: t.channel,
            status: 'ready',
            updatedAt: t.updatedAt,
            readyAt: readyAt,
          ));
        }
      }
    }

    // Detect newly ready orders → play chime.
    final newReadyIds = ready.map((o) => o.id).toSet();
    final brandNewReady = newReadyIds.difference(_previousReadyIds);
    if (brandNewReady.isNotEmpty && _ref.read(odsSoundEnabledProvider)) {
      _playChime();
    }
    _previousReadyIds = newReadyIds;

    state = state.copyWith(preparing: preparing, ready: ready);
  }

  void _playChime() {
    SystemSound.play(SystemSoundType.click);
  }

  void _startAutoRemoveTimer() {
    _autoRemoveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (state.ready.isEmpty) return;
      final autoRemoveMinutes = _ref.read(odsAutoRemoveMinutesProvider);
      final now = DateTime.now();
      final stillVisible = state.ready.where((o) {
        final age = now.difference(o.readyAt ?? now);
        return age.inMinutes < autoRemoveMinutes;
      }).toList();

      if (stillVisible.length != state.ready.length) {
        state = state.copyWith(ready: stillVisible);
      }
    });
  }

  void setConnected(bool connected) {
    state = state.copyWith(isConnected: connected);
  }

  @override
  void dispose() {
    _ticketSub?.cancel();
    _autoRemoveTimer?.cancel();
    super.dispose();
  }
}

/// The main ODS state provider.
final odsProvider = StateNotifierProvider<OdsNotifier, OdsState>((ref) {
  final db = ref.watch(databaseProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return OdsNotifier(db: db, tenantId: tenantId, ref: ref);
});
