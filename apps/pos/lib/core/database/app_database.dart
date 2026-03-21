import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:gastrocore_pos/features/audit_log/data/daos/audit_log_dao.dart';
import 'package:gastrocore_pos/features/sync/data/daos/sync_event_dao.dart';

import 'tables/audit_log.dart';
import 'tables/bills.dart';
import 'tables/cash_movements.dart';
import 'tables/categories.dart';
import 'tables/combo_items.dart';
import 'tables/day_close_summaries.dart';
import 'tables/floors.dart';
import 'tables/kitchen_ticket_items.dart';
import 'tables/kitchen_tickets.dart';
import 'tables/modifier_groups.dart';
import 'tables/modifiers.dart';
import 'tables/order_item_modifiers.dart';
import 'tables/order_items.dart';
import 'tables/order_type_rules.dart';
import 'tables/payments.dart';
import 'tables/product_modifier_groups.dart';
import 'tables/product_prices.dart';
import 'tables/product_specifications.dart';
import 'tables/products.dart';
import 'tables/receipts.dart';
import 'tables/restaurant_tables.dart';
import 'tables/shifts.dart';
import 'tables/sync_metadata.dart';
import 'tables/sync_queue.dart';
import 'tables/tax_profiles.dart';
import 'tables/tenants.dart';
import 'tables/tickets.dart';
import 'tables/users.dart';
import 'tables/license_tokens.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Tenants,
    Users,
    Categories,
    Products,
    ModifierGroups,
    Modifiers,
    ProductModifierGroups,
    Floors,
    RestaurantTables,
    Tickets,
    OrderItems,
    OrderItemModifiers,
    Bills,
    Payments,
    Shifts,
    CashMovements,
    KitchenTickets,
    KitchenTicketItems,
    Receipts,
    SyncQueue,
    SyncMetadata,
    AuditLog,
    TaxProfiles,
    ProductPrices,
    OrderTypeRules,
    ComboItems,
    ProductSpecifications,
    LicenseTokens,
    DayCloseSummaries,
  ],
  daos: [AuditLogDao, SyncEventDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(users, users.avatarPath);
      }
      if (from < 3) {
        await m.addColumn(kitchenTickets, kitchenTickets.waiterName);
      }
      if (from < 4) {
        // Add columns introduced in v4 to the audit_log table.
        await m.addColumn(auditLog, auditLog.userName);
        await m.addColumn(auditLog, auditLog.reason);
        await m.addColumn(auditLog, auditLog.ipAddress);
      }
      if (from < 5) {
        // Add license_tokens table introduced in v5.
        await m.createTable(licenseTokens);
      }
      if (from < 6) {
        // Add day_close_summaries table introduced in v6.
        await m.createTable(dayCloseSummaries);
      }
    },
    onCreate: (m) async {
      await m.createAll();
    },
  );

  /// Create a database backed by a file in the app documents directory.
  static AppDatabase create() {
    return AppDatabase(
      LazyDatabase(() async {
        final dbFolder = await getApplicationDocumentsDirectory();
        final file = File(p.join(dbFolder.path, 'gastrocore_pos.sqlite'));
        return NativeDatabase.createInBackground(file);
      }),
    );
  }

  /// Create an in-memory database for testing.
  ///
  /// Uses [closeStreamsSynchronously] so that Drift stream queries are
  /// cleaned up immediately when their last listener detaches. This avoids
  /// pending-timer assertion failures in Flutter widget tests that use
  /// FakeAsync (see https://drift.simonbinder.eu/faq/).
  static AppDatabase createInMemory() {
    return AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  }
}
