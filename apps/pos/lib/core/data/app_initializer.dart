/// Application initializer for GastroCore POS.
///
/// Runs one-time setup tasks such as database seeding before the app
/// renders its first frame. Call [initialize] from `main()` after creating
/// the [AppDatabase] instance.
library;

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/data/seed_data.dart';

/// Bootstraps the application by running all required initialization steps.
class AppInitializer {
  /// Run all initialization tasks.
  ///
  /// Currently this seeds the database with demo data if it is empty.
  /// Future steps (e.g. loading cached settings, syncing with backend)
  /// can be added here.
  static Future<void> initialize(AppDatabase db) async {
    final seeder = SeedData(db);
    await seeder.seedIfEmpty();
  }
}
