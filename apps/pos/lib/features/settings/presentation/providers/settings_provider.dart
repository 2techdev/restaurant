/// Riverpod providers for the Settings module.
///
/// Each settings category gets its own [StateNotifierProvider] so widgets
/// can watch only the slice of state they need. All notifiers are lazy-loaded
/// and immediately trigger a load from [SettingsRepository] on creation.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/app_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/happy_hour_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/loyalty_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/payment_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/printer_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/receipt_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/tax_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/theme_customization.dart';
import 'package:gastrocore_pos/features/settings/domain/repositories/settings_repository.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// Async provider that creates a [SharedPreferences] instance and wraps it
/// in [SettingsRepositoryImpl].
///
/// Consumed by every settings notifier so preferences are shared.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

/// [SettingsRepository] provider, backed by [SettingsRepositoryImpl].
///
/// Waits for [SharedPreferences] to be ready; exposes an [AsyncValue] so
/// callers can handle loading / error states.
final settingsRepositoryProvider =
    FutureProvider<SettingsRepository>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return SettingsRepositoryImpl(prefs);
});

// ---------------------------------------------------------------------------
// Restaurant Settings
// ---------------------------------------------------------------------------

class RestaurantSettingsNotifier
    extends StateNotifier<AsyncValue<RestaurantSettings>> {
  RestaurantSettingsNotifier(this._repository)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final SettingsRepository _repository;

  Future<void> _load() async {
    state = await AsyncValue.guard(_repository.loadRestaurantSettings);
  }

  Future<void> save(RestaurantSettings settings) async {
    await _repository.saveRestaurantSettings(settings);
    state = AsyncValue.data(settings);
  }

  Future<void> update(RestaurantSettings Function(RestaurantSettings) updater) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await save(updater(current));
  }
}

final restaurantSettingsProvider = StateNotifierProvider<
    RestaurantSettingsNotifier, AsyncValue<RestaurantSettings>>((ref) {
  final repo = ref.watch(settingsRepositoryProvider).valueOrNull;
  if (repo == null) {
    // Repository not ready yet — return a notifier that stays loading.
    return _LoadingNotifier<RestaurantSettings, RestaurantSettingsNotifier>(
      () => RestaurantSettingsNotifier(_PlaceholderRepository()),
    ).create();
  }
  return RestaurantSettingsNotifier(repo);
});

// ---------------------------------------------------------------------------
// Printer Settings
// ---------------------------------------------------------------------------

class PrinterSettingsNotifier
    extends StateNotifier<AsyncValue<PrinterSettings>> {
  PrinterSettingsNotifier(this._repository)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final SettingsRepository _repository;

  Future<void> _load() async {
    state = await AsyncValue.guard(_repository.loadPrinterSettings);
  }

  Future<void> save(PrinterSettings settings) async {
    await _repository.savePrinterSettings(settings);
    state = AsyncValue.data(settings);
  }

  Future<void> update(PrinterSettings Function(PrinterSettings) updater) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await save(updater(current));
  }
}

final printerSettingsProvider = StateNotifierProvider<PrinterSettingsNotifier,
    AsyncValue<PrinterSettings>>((ref) {
  final repo = ref.watch(settingsRepositoryProvider).valueOrNull;
  if (repo == null) return PrinterSettingsNotifier(_PlaceholderRepository());
  return PrinterSettingsNotifier(repo);
});

// ---------------------------------------------------------------------------
// Payment Settings
// ---------------------------------------------------------------------------

class PaymentSettingsNotifier
    extends StateNotifier<AsyncValue<PaymentSettings>> {
  PaymentSettingsNotifier(this._repository)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final SettingsRepository _repository;

  Future<void> _load() async {
    state = await AsyncValue.guard(_repository.loadPaymentSettings);
  }

  Future<void> save(PaymentSettings settings) async {
    await _repository.savePaymentSettings(settings);
    state = AsyncValue.data(settings);
  }

  Future<void> update(PaymentSettings Function(PaymentSettings) updater) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await save(updater(current));
  }
}

final paymentSettingsProvider = StateNotifierProvider<PaymentSettingsNotifier,
    AsyncValue<PaymentSettings>>((ref) {
  final repo = ref.watch(settingsRepositoryProvider).valueOrNull;
  if (repo == null) return PaymentSettingsNotifier(_PlaceholderRepository());
  return PaymentSettingsNotifier(repo);
});

// ---------------------------------------------------------------------------
// Receipt Settings
// ---------------------------------------------------------------------------

class ReceiptSettingsNotifier
    extends StateNotifier<AsyncValue<ReceiptSettings>> {
  ReceiptSettingsNotifier(this._repository)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final SettingsRepository _repository;

  Future<void> _load() async {
    state = await AsyncValue.guard(_repository.loadReceiptSettings);
  }

  Future<void> save(ReceiptSettings settings) async {
    await _repository.saveReceiptSettings(settings);
    state = AsyncValue.data(settings);
  }

  Future<void> update(ReceiptSettings Function(ReceiptSettings) updater) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await save(updater(current));
  }
}

final receiptSettingsProvider = StateNotifierProvider<ReceiptSettingsNotifier,
    AsyncValue<ReceiptSettings>>((ref) {
  final repo = ref.watch(settingsRepositoryProvider).valueOrNull;
  if (repo == null) return ReceiptSettingsNotifier(_PlaceholderRepository());
  return ReceiptSettingsNotifier(repo);
});

// ---------------------------------------------------------------------------
// Tax Settings
// ---------------------------------------------------------------------------

class TaxSettingsNotifier extends StateNotifier<AsyncValue<TaxSettings>> {
  TaxSettingsNotifier(this._repository) : super(const AsyncValue.loading()) {
    _load();
  }

  final SettingsRepository _repository;

  Future<void> _load() async {
    state = await AsyncValue.guard(_repository.loadTaxSettings);
  }

  Future<void> save(TaxSettings settings) async {
    await _repository.saveTaxSettings(settings);
    state = AsyncValue.data(settings);
  }

  Future<void> update(TaxSettings Function(TaxSettings) updater) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await save(updater(current));
  }

  /// Resets all rates to Swiss MWST defaults (effective 01.01.2024).
  Future<void> resetToSwissDefaults() async {
    await save(TaxSettings());
  }
}

final taxSettingsProvider =
    StateNotifierProvider<TaxSettingsNotifier, AsyncValue<TaxSettings>>((ref) {
  final repo = ref.watch(settingsRepositoryProvider).valueOrNull;
  if (repo == null) return TaxSettingsNotifier(_PlaceholderRepository());
  return TaxSettingsNotifier(repo);
});

// ---------------------------------------------------------------------------
// App Settings (theme / language)
// ---------------------------------------------------------------------------

class AppSettingsNotifier extends StateNotifier<AsyncValue<AppSettings>> {
  AppSettingsNotifier(this._repository) : super(const AsyncValue.loading()) {
    _load();
  }

  final SettingsRepository _repository;

  Future<void> _load() async {
    state = await AsyncValue.guard(_repository.loadAppSettings);
  }

  Future<void> save(AppSettings settings) async {
    await _repository.saveAppSettings(settings);
    state = AsyncValue.data(settings);
  }

  Future<void> setTheme(AppThemeMode mode) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(themeMode: mode));
  }

  Future<void> setLanguage(AppLanguage language) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(language: language));
  }

  Future<void> setHandedness(AppHandedness handedness) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(handedness: handedness));
  }

  Future<void> setHighContrast(bool enabled) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(highContrast: enabled));
  }

  Future<void> setTextScale(AppTextScale scale) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(textScale: scale));
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AsyncValue<AppSettings>>((ref) {
  final repo = ref.watch(settingsRepositoryProvider).valueOrNull;
  if (repo == null) return AppSettingsNotifier(_PlaceholderRepository());
  return AppSettingsNotifier(repo);
});

// ---------------------------------------------------------------------------
// Theme customization (operator-picked accent + surface colours)
// ---------------------------------------------------------------------------

class ThemeCustomizationNotifier
    extends StateNotifier<AsyncValue<ThemeCustomization>> {
  ThemeCustomizationNotifier(this._repository)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final SettingsRepository _repository;

  Future<void> _load() async {
    state = await AsyncValue.guard(_repository.loadThemeCustomization);
  }

  Future<void> save(ThemeCustomization customization) async {
    await _repository.saveThemeCustomization(customization);
    state = AsyncValue.data(customization);
  }

  Future<void> setLightPrimary(String? hex) async {
    final current = state.valueOrNull ?? const ThemeCustomization();
    await save(current.copyWith(
      lightPrimaryHex: hex,
      clearLightPrimary: hex == null,
    ));
  }

  Future<void> setDarkPrimary(String? hex) async {
    final current = state.valueOrNull ?? const ThemeCustomization();
    await save(current.copyWith(
      darkPrimaryHex: hex,
      clearDarkPrimary: hex == null,
    ));
  }

  Future<void> setLightSurface(String? hex) async {
    final current = state.valueOrNull ?? const ThemeCustomization();
    await save(current.copyWith(
      lightSurfaceHex: hex,
      clearLightSurface: hex == null,
    ));
  }

  Future<void> setDarkSurface(String? hex) async {
    final current = state.valueOrNull ?? const ThemeCustomization();
    await save(current.copyWith(
      darkSurfaceHex: hex,
      clearDarkSurface: hex == null,
    ));
  }

  Future<void> restoreDefaults() async {
    await save(const ThemeCustomization());
  }
}

final themeCustomizationProvider = StateNotifierProvider<
    ThemeCustomizationNotifier, AsyncValue<ThemeCustomization>>((ref) {
  final repo = ref.watch(settingsRepositoryProvider).valueOrNull;
  if (repo == null) {
    return ThemeCustomizationNotifier(_PlaceholderRepository());
  }
  return ThemeCustomizationNotifier(repo);
});

// ---------------------------------------------------------------------------
// Loyalty Settings (earn / redemption / tier thresholds)
// ---------------------------------------------------------------------------

class LoyaltySettingsNotifier
    extends StateNotifier<AsyncValue<LoyaltySettings>> {
  LoyaltySettingsNotifier(this._repository)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final SettingsRepository _repository;

  Future<void> _load() async {
    state = await AsyncValue.guard(_repository.loadLoyaltySettings);
  }

  Future<void> save(LoyaltySettings settings) async {
    await _repository.saveLoyaltySettings(settings);
    state = AsyncValue.data(settings);
  }

  Future<void> update(
    LoyaltySettings Function(LoyaltySettings) updater,
  ) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await save(updater(current));
  }

  /// Restores the factory defaults matching the legacy hard-coded rules
  /// (1 pt/CHF, 1 ct/pt, Silber CHF 200, Gold CHF 500). Used by the "Reset"
  /// button in the editor and by the pilot smoke tests.
  Future<void> resetToDefaults() async {
    await save(const LoyaltySettings());
  }
}

final loyaltySettingsProvider = StateNotifierProvider<LoyaltySettingsNotifier,
    AsyncValue<LoyaltySettings>>((ref) {
  final repo = ref.watch(settingsRepositoryProvider).valueOrNull;
  if (repo == null) return LoyaltySettingsNotifier(_PlaceholderRepository());
  return LoyaltySettingsNotifier(repo);
});

// ---------------------------------------------------------------------------
// Backup provider (one-shot async operations)
// ---------------------------------------------------------------------------

/// Provides the live database path for display in the Backup section.
final databasePathProvider = FutureProvider<String>((ref) async {
  final repo = await ref.watch(settingsRepositoryProvider.future);
  return repo.getDatabasePath();
});

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// Placeholder repository used while SharedPreferences is still loading.
// Keeps notifiers in the loading state without throwing.
class _PlaceholderRepository implements SettingsRepository {
  @override
  Future<RestaurantSettings> loadRestaurantSettings() async =>
      const RestaurantSettings();
  @override
  Future<void> saveRestaurantSettings(RestaurantSettings s) async {}
  @override
  Future<PrinterSettings> loadPrinterSettings() async =>
      const PrinterSettings();
  @override
  Future<void> savePrinterSettings(PrinterSettings s) async {}
  @override
  Future<PaymentSettings> loadPaymentSettings() async =>
      const PaymentSettings();
  @override
  Future<void> savePaymentSettings(PaymentSettings s) async {}
  @override
  Future<ReceiptSettings> loadReceiptSettings() async =>
      const ReceiptSettings();
  @override
  Future<void> saveReceiptSettings(ReceiptSettings s) async {}
  @override
  Future<TaxSettings> loadTaxSettings() async => TaxSettings();
  @override
  Future<void> saveTaxSettings(TaxSettings s) async {}
  @override
  Future<AppSettings> loadAppSettings() async => const AppSettings();
  @override
  Future<void> saveAppSettings(AppSettings s) async {}
  @override
  Future<ThemeCustomization> loadThemeCustomization() async =>
      const ThemeCustomization();
  @override
  Future<void> saveThemeCustomization(ThemeCustomization c) async {}
  @override
  Future<HappyHourSettings> loadHappyHourSettings() async =>
      const HappyHourSettings();
  @override
  Future<void> saveHappyHourSettings(HappyHourSettings s) async {}
  @override
  Future<LoyaltySettings> loadLoyaltySettings() async =>
      const LoyaltySettings();
  @override
  Future<void> saveLoyaltySettings(LoyaltySettings s) async {}
  @override
  Future<String> getDatabasePath() async => '';
  @override
  Future<String> exportDatabase(String targetDirectory) async => '';
  @override
  Future<void> importDatabase(String sourcePath) async {}
  @override
  Future<void> clearAll() async {}
}

// Simple helper to make the "repo not ready" branch compile without repetition.
class _LoadingNotifier<T, N extends StateNotifier<AsyncValue<T>>> {
  _LoadingNotifier(this._factory);
  final N Function() _factory;
  N create() => _factory();
}
