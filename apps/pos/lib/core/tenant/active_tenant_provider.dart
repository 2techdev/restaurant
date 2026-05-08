import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and exposes the *currently selected* tenant ID for an operator
/// who has been granted access to multiple tenants (multi-restaurant
/// operator). Defaults to the device's primary tenant (the value bound to
/// [tenantIdProvider] at app startup) when no override is stored.
///
/// The runtime tenant switcher is gated by AppSettings.multiTenantSwitcherEnabled
/// (default false). When the flag is off, this notifier still exists so
/// callers can read it uniformly, but the value will always equal the
/// primary tenant.
class ActiveTenantNotifier extends StateNotifier<String> {
  ActiveTenantNotifier({
    required this.primaryTenantId,
    SharedPreferences? prefs,
  }) : _prefs = prefs,
       super(prefs?.getString(_kPrefKey) ?? primaryTenantId);

  static const _kPrefKey = 'active_tenant_id';

  final String primaryTenantId;
  SharedPreferences? _prefs;

  /// Loads the persisted tenant ID. Idempotent — calling twice is safe.
  Future<void> hydrate() async {
    _prefs ??= await SharedPreferences.getInstance();
    final saved = _prefs!.getString(_kPrefKey);
    if (saved != null && saved.isNotEmpty && saved != state) {
      state = saved;
    }
  }

  /// Switch to [tenantId]. Persists immediately so a process restart picks
  /// the new tenant. Callers should follow up with a cloud-sync trigger to
  /// pull the new tenant's menu / categories / modifiers before the next
  /// order is keyed in.
  Future<void> switchTo(String tenantId) async {
    if (tenantId.isEmpty || tenantId == state) return;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kPrefKey, tenantId);
    state = tenantId;
  }

  /// Reset to the device's primary tenant (used at logout or when the user
  /// loses access to the previously selected tenant).
  Future<void> resetToPrimary() async => switchTo(primaryTenantId);
}

/// Provider for the runtime-selected tenant. The override at app startup
/// must supply the primary tenant ID (same value bound to [tenantIdProvider]
/// in core/di/providers.dart). Until the runtime switcher feature flag is
/// enabled, [ActiveTenantNotifier.state] always equals primaryTenantId.
final activeTenantProvider =
    StateNotifierProvider<ActiveTenantNotifier, String>((ref) {
  throw UnimplementedError(
    'activeTenantProvider must be overridden in main.dart with the primary '
    'tenant ID. See core/tenant/active_tenant_provider.dart for usage.',
  );
});
