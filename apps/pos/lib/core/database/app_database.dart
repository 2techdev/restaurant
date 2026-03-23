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
import 'tables/fiscal_signatures.dart';
import 'tables/lan_sync_peers.dart';
import 'tables/manager_pins.dart';

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
    FiscalSignatures,
    LanSyncPeers,
    ManagerPins,
  ],
  daos: [AuditLogDao, SyncEventDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 7;

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
      if (from < 7) {
        // v7: new tables for fiscal signing (Germany TSE), LAN peer sync,
        // and manager PIN audit trail.
        await m.createTable(fiscalSignatures);
        await m.createTable(lanSyncPeers);
        await m.createTable(managerPins);

        // Performance indexes on high-frequency query columns.
        // tickets: status filter + date range queries.
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_tickets_tenant_status '
          'ON tickets (tenant_id, status) '
          'WHERE is_deleted = 0',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_tickets_tenant_opened_at '
          'ON tickets (tenant_id, opened_at DESC) '
          'WHERE is_deleted = 0',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_tickets_table_id '
          'ON tickets (table_id) '
          'WHERE table_id IS NOT NULL AND is_deleted = 0',
        );
        // order_items: look up items by ticket.
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_order_items_ticket_id '
          'ON order_items (ticket_id) '
          'WHERE is_deleted = 0',
        );
        // payments: join from ticket or bill.
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_payments_ticket_id '
          'ON payments (ticket_id) '
          'WHERE is_deleted = 0',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_payments_bill_id '
          'ON payments (bill_id) '
          'WHERE is_deleted = 0',
        );
        // audit_log: tenant + timestamp for chronological queries.
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_audit_log_tenant_timestamp '
          'ON audit_log (tenant_id, timestamp DESC)',
        );
        // license_tokens: quick look-up of active token per tenant.
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_license_tokens_tenant_active '
          'ON license_tokens (tenant_id, is_active)',
        );
        // fiscal_signatures: look up by receipt.
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_fiscal_signatures_receipt_id '
          'ON fiscal_signatures (receipt_id)',
        );
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
