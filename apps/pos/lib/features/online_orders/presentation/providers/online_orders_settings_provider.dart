/// Operator-facing Settings for the Online Bestellungen feature.
///
/// Two providers:
///   - [onlineOrdersConfigProvider] (`AsyncNotifier`) reads the persisted
///     config from SharedPreferences on first read, exposes the current
///     [OnlineOrdersConfig] and mutators.
///   - [onlineOrdersEnabledProvider] is a thin synchronous bool view used
///     by the rail / boot wire so they don't have to unwrap the AsyncValue.
///
/// Faz 3 scope: toggle + sound + auto-print + lead-time minutes. The
/// gastro.2hub.ch tenant override + API token fields are stubbed in
/// the entity so the Settings UI lays out the full mock — the WS
/// pump still reads tenant/device from the existing `tenantIdProvider`
/// because the pilot operator pairs the device through the normal
/// Brand login. Faz 4+ can flip the WS client to honour the override.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';

class OnlineOrdersConfig {
  const OnlineOrdersConfig({
    this.enabled = false,
    this.soundOn = true,
    this.autoPrintOnAccept = false,
    this.leadTimeMinutes = 30,
    this.tenantOverride = '',
    this.apiToken = '',
    this.popupStyle = OnlinePopupStyle.toast,
  });

  final bool enabled;
  final bool soundOn;
  final bool autoPrintOnAccept;
  final int leadTimeMinutes;
  final String tenantOverride;
  final String apiToken;
  final OnlinePopupStyle popupStyle;

  OnlineOrdersConfig copyWith({
    bool? enabled,
    bool? soundOn,
    bool? autoPrintOnAccept,
    int? leadTimeMinutes,
    String? tenantOverride,
    String? apiToken,
    OnlinePopupStyle? popupStyle,
  }) {
    return OnlineOrdersConfig(
      enabled: enabled ?? this.enabled,
      soundOn: soundOn ?? this.soundOn,
      autoPrintOnAccept: autoPrintOnAccept ?? this.autoPrintOnAccept,
      leadTimeMinutes: leadTimeMinutes ?? this.leadTimeMinutes,
      tenantOverride: tenantOverride ?? this.tenantOverride,
      apiToken: apiToken ?? this.apiToken,
      popupStyle: popupStyle ?? this.popupStyle,
    );
  }
}

enum OnlinePopupStyle { toast, modal }

const _kEnabled = 'online_orders.enabled';
const _kSoundOn = 'online_orders.sound_on';
const _kAutoPrint = 'online_orders.auto_print';
const _kLeadTime = 'online_orders.lead_time_minutes';
const _kTenant = 'online_orders.tenant_override';
const _kToken = 'online_orders.api_token';
const _kPopupStyle = 'online_orders.popup_style';

class OnlineOrdersConfigNotifier extends StateNotifier<OnlineOrdersConfig> {
  OnlineOrdersConfigNotifier(this._prefs) : super(_readInitial(_prefs));

  final SharedPreferences? _prefs;

  static OnlineOrdersConfig _readInitial(SharedPreferences? p) {
    if (p == null) return const OnlineOrdersConfig();
    return OnlineOrdersConfig(
      enabled: p.getBool(_kEnabled) ?? false,
      soundOn: p.getBool(_kSoundOn) ?? true,
      autoPrintOnAccept: p.getBool(_kAutoPrint) ?? false,
      leadTimeMinutes: p.getInt(_kLeadTime) ?? 30,
      tenantOverride: p.getString(_kTenant) ?? '',
      apiToken: p.getString(_kToken) ?? '',
      popupStyle: (p.getString(_kPopupStyle) ?? 'toast') == 'modal'
          ? OnlinePopupStyle.modal
          : OnlinePopupStyle.toast,
    );
  }

  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v);
    await _prefs?.setBool(_kEnabled, v);
  }

  Future<void> setSoundOn(bool v) async {
    state = state.copyWith(soundOn: v);
    await _prefs?.setBool(_kSoundOn, v);
  }

  Future<void> setAutoPrint(bool v) async {
    state = state.copyWith(autoPrintOnAccept: v);
    await _prefs?.setBool(_kAutoPrint, v);
  }

  Future<void> setLeadTime(int minutes) async {
    final clamped = minutes.clamp(5, 180);
    state = state.copyWith(leadTimeMinutes: clamped);
    await _prefs?.setInt(_kLeadTime, clamped);
  }

  Future<void> setTenantOverride(String v) async {
    state = state.copyWith(tenantOverride: v.trim());
    await _prefs?.setString(_kTenant, v.trim());
  }

  Future<void> setApiToken(String v) async {
    state = state.copyWith(apiToken: v.trim());
    await _prefs?.setString(_kToken, v.trim());
  }

  Future<void> setPopupStyle(OnlinePopupStyle s) async {
    state = state.copyWith(popupStyle: s);
    await _prefs?.setString(_kPopupStyle,
        s == OnlinePopupStyle.modal ? 'modal' : 'toast');
  }
}

final onlineOrdersConfigProvider = StateNotifierProvider<
    OnlineOrdersConfigNotifier, OnlineOrdersConfig>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).valueOrNull;
  return OnlineOrdersConfigNotifier(prefs);
});

/// Convenience: synchronous "is online orders enabled?" lookup used by
/// the rail entry visibility and the WS boot gate. Watching this only
/// rebuilds dependents when the boolean flips, not on every config
/// field change.
final onlineOrdersEnabledProvider = Provider<bool>((ref) {
  return ref.watch(onlineOrdersConfigProvider.select((c) => c.enabled));
});
