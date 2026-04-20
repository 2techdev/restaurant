/// Abstract settings repository interface.
///
/// Decouples the presentation / domain layers from the concrete
/// SharedPreferences storage implementation.
library;

import 'package:gastrocore_pos/features/settings/domain/entities/app_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/payment_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/printer_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/receipt_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/tax_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/theme_customization.dart';

abstract interface class SettingsRepository {
  // ---------------------------------------------------------------------------
  // Restaurant
  // ---------------------------------------------------------------------------

  Future<RestaurantSettings> loadRestaurantSettings();
  Future<void> saveRestaurantSettings(RestaurantSettings settings);

  // ---------------------------------------------------------------------------
  // Printer
  // ---------------------------------------------------------------------------

  Future<PrinterSettings> loadPrinterSettings();
  Future<void> savePrinterSettings(PrinterSettings settings);

  // ---------------------------------------------------------------------------
  // Payment
  // ---------------------------------------------------------------------------

  Future<PaymentSettings> loadPaymentSettings();
  Future<void> savePaymentSettings(PaymentSettings settings);

  // ---------------------------------------------------------------------------
  // Receipt
  // ---------------------------------------------------------------------------

  Future<ReceiptSettings> loadReceiptSettings();
  Future<void> saveReceiptSettings(ReceiptSettings settings);

  // ---------------------------------------------------------------------------
  // Tax
  // ---------------------------------------------------------------------------

  Future<TaxSettings> loadTaxSettings();
  Future<void> saveTaxSettings(TaxSettings settings);

  // ---------------------------------------------------------------------------
  // App (theme / language)
  // ---------------------------------------------------------------------------

  Future<AppSettings> loadAppSettings();
  Future<void> saveAppSettings(AppSettings settings);

  // ---------------------------------------------------------------------------
  // Theme customization (operator-picked accent + surface colours)
  // ---------------------------------------------------------------------------

  Future<ThemeCustomization> loadThemeCustomization();
  Future<void> saveThemeCustomization(ThemeCustomization customization);

  // ---------------------------------------------------------------------------
  // Backup & Restore
  // ---------------------------------------------------------------------------

  /// Returns the absolute path of the live SQLite database file.
  Future<String> getDatabasePath();

  /// Copies the SQLite database to [targetDirectory].
  ///
  /// Returns the full path of the created backup file.
  /// Throws [SettingsException] on failure.
  Future<String> exportDatabase(String targetDirectory);

  /// Replaces the current SQLite database with the file at [sourcePath].
  ///
  /// The app must be restarted after import for changes to take effect.
  /// Throws [SettingsException] on failure.
  Future<void> importDatabase(String sourcePath);

  // ---------------------------------------------------------------------------
  // Nuclear reset
  // ---------------------------------------------------------------------------

  /// Clears all persisted settings, reverting to factory defaults.
  Future<void> clearAll();
}

/// Exception thrown by [SettingsRepository] operations.
class SettingsException implements Exception {
  const SettingsException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause != null
      ? 'SettingsException: $message (cause: $cause)'
      : 'SettingsException: $message';
}
