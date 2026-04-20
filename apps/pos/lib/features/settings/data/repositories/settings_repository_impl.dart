/// SharedPreferences-backed implementation of [SettingsRepository].
///
/// Each settings category is stored as a single JSON string under a
/// dedicated key. This keeps the preference namespace clean and allows
/// atomic updates per category.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/features/settings/domain/entities/app_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/payment_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/printer_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/receipt_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/tax_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/theme_customization.dart';
import 'package:gastrocore_pos/features/settings/domain/repositories/settings_repository.dart';

/// SharedPreferences keys — prefixed to avoid collisions with other features.
abstract final class _Keys {
  static const restaurant = 'settings.v1.restaurant';
  static const printer = 'settings.v1.printer';
  static const payment = 'settings.v1.payment';
  static const receipt = 'settings.v1.receipt';
  static const tax = 'settings.v1.tax';
  static const app = 'settings.v1.app';
  static const themeColors = 'settings.v1.themeColors';
}

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._prefs);

  final SharedPreferences _prefs;

  // ---------------------------------------------------------------------------
  // Restaurant
  // ---------------------------------------------------------------------------

  @override
  Future<RestaurantSettings> loadRestaurantSettings() async {
    final raw = _prefs.getString(_Keys.restaurant);
    if (raw == null) return const RestaurantSettings();
    try {
      return RestaurantSettings.fromJsonString(raw);
    } catch (_) {
      return const RestaurantSettings();
    }
  }

  @override
  Future<void> saveRestaurantSettings(RestaurantSettings settings) async {
    await _prefs.setString(_Keys.restaurant, settings.toJsonString());
  }

  // ---------------------------------------------------------------------------
  // Printer
  // ---------------------------------------------------------------------------

  @override
  Future<PrinterSettings> loadPrinterSettings() async {
    final raw = _prefs.getString(_Keys.printer);
    if (raw == null) return const PrinterSettings();
    try {
      return PrinterSettings.fromJsonString(raw);
    } catch (_) {
      return const PrinterSettings();
    }
  }

  @override
  Future<void> savePrinterSettings(PrinterSettings settings) async {
    await _prefs.setString(_Keys.printer, settings.toJsonString());
  }

  // ---------------------------------------------------------------------------
  // Payment
  // ---------------------------------------------------------------------------

  @override
  Future<PaymentSettings> loadPaymentSettings() async {
    final raw = _prefs.getString(_Keys.payment);
    if (raw == null) return const PaymentSettings();
    try {
      return PaymentSettings.fromJsonString(raw);
    } catch (_) {
      return const PaymentSettings();
    }
  }

  @override
  Future<void> savePaymentSettings(PaymentSettings settings) async {
    await _prefs.setString(_Keys.payment, settings.toJsonString());
  }

  // ---------------------------------------------------------------------------
  // Receipt
  // ---------------------------------------------------------------------------

  @override
  Future<ReceiptSettings> loadReceiptSettings() async {
    final raw = _prefs.getString(_Keys.receipt);
    if (raw == null) return const ReceiptSettings();
    try {
      return ReceiptSettings.fromJsonString(raw);
    } catch (_) {
      return const ReceiptSettings();
    }
  }

  @override
  Future<void> saveReceiptSettings(ReceiptSettings settings) async {
    await _prefs.setString(_Keys.receipt, settings.toJsonString());
  }

  // ---------------------------------------------------------------------------
  // Tax
  // ---------------------------------------------------------------------------

  @override
  Future<TaxSettings> loadTaxSettings() async {
    final raw = _prefs.getString(_Keys.tax);
    if (raw == null) return TaxSettings();
    try {
      return TaxSettings.fromJsonString(raw);
    } catch (_) {
      return TaxSettings();
    }
  }

  @override
  Future<void> saveTaxSettings(TaxSettings settings) async {
    await _prefs.setString(_Keys.tax, settings.toJsonString());
  }

  // ---------------------------------------------------------------------------
  // App (theme / language)
  // ---------------------------------------------------------------------------

  @override
  Future<AppSettings> loadAppSettings() async {
    final raw = _prefs.getString(_Keys.app);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJsonString(raw);
    } catch (_) {
      return const AppSettings();
    }
  }

  @override
  Future<void> saveAppSettings(AppSettings settings) async {
    await _prefs.setString(_Keys.app, settings.toJsonString());
  }

  // ---------------------------------------------------------------------------
  // Theme customization
  // ---------------------------------------------------------------------------

  @override
  Future<ThemeCustomization> loadThemeCustomization() async {
    final raw = _prefs.getString(_Keys.themeColors);
    if (raw == null) return const ThemeCustomization();
    try {
      return ThemeCustomization.fromJsonString(raw);
    } catch (_) {
      return const ThemeCustomization();
    }
  }

  @override
  Future<void> saveThemeCustomization(ThemeCustomization customization) async {
    await _prefs.setString(_Keys.themeColors, customization.toJsonString());
  }

  // ---------------------------------------------------------------------------
  // Backup & Restore
  // ---------------------------------------------------------------------------

  @override
  Future<String> getDatabasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'gastrocore_pos.sqlite');
  }

  @override
  Future<String> exportDatabase(String targetDirectory) async {
    final dbPath = await getDatabasePath();
    final source = File(dbPath);

    if (!source.existsSync()) {
      throw const SettingsException('Database file not found.');
    }

    final target = Directory(targetDirectory);
    if (!target.existsSync()) {
      await target.create(recursive: true);
    }

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);
    final destPath = p.join(targetDirectory, 'gastrocore_backup_$timestamp.sqlite');

    try {
      await source.copy(destPath);
    } catch (e) {
      throw SettingsException('Failed to export database.', cause: e);
    }

    return destPath;
  }

  @override
  Future<void> importDatabase(String sourcePath) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw SettingsException('Backup file not found: $sourcePath');
    }

    final dbPath = await getDatabasePath();
    try {
      await source.copy(dbPath);
    } catch (e) {
      throw SettingsException('Failed to import database.', cause: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Nuclear reset
  // ---------------------------------------------------------------------------

  @override
  Future<void> clearAll() async {
    await Future.wait([
      _prefs.remove(_Keys.restaurant),
      _prefs.remove(_Keys.printer),
      _prefs.remove(_Keys.payment),
      _prefs.remove(_Keys.receipt),
      _prefs.remove(_Keys.tax),
      _prefs.remove(_Keys.app),
      _prefs.remove(_Keys.themeColors),
    ]);
  }
}
