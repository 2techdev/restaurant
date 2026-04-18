import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:gastrocore_pos/features/audit_log/data/daos/audit_log_dao.dart';
import 'package:gastrocore_pos/features/inventory/data/daos/inventory_dao.dart';
import 'package:gastrocore_pos/features/sync/data/daos/sync_event_dao.dart';

import 'tables/audit_log.dart';
import 'tables/bills.dart';
import 'tables/gang_templates.dart';
import 'tables/order_gang_states.dart';
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
import 'tables/stations.dart';
import 'tables/sync_metadata.dart';
import 'tables/sync_queue.dart';
import 'tables/tax_profiles.dart';
import 'tables/tenants.dart';
import 'tables/tickets.dart';
import 'tables/users.dart';
import 'tables/inventory_items.dart';
import 'tables/inventory_transactions.dart';
import 'tables/license_tokens.dart';
import 'tables/suppliers.dart';
import 'tables/reservations.dart';
import 'tables/customers.dart';
import 'tables/customer_addresses.dart';
import 'tables/loyalty_transactions.dart';
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
    InventoryItems,
    InventoryTransactions,
    Suppliers,
    Reservations,
    Customers,
    CustomerAddresses,
    LoyaltyTransactions,
    FiscalSignatures,
    LanSyncPeers,
    ManagerPins,
    GangTemplates,
    OrderGangStates,
    Stations,
  ],
  daos: [AuditLogDao, InventoryDao, SyncEventDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 10;

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
        // v7: inventory tables, CRM, fiscal signing (Germany TSE), LAN peer sync,
        // manager PIN audit trail, and performance indexes.
        await m.createTable(inventoryItems);
        await m.createTable(inventoryTransactions);
        await m.createTable(suppliers);
        await m.createTable(reservations);
        await m.addColumn(users, users.managerPinHash);
        await m.addColumn(auditLog, auditLog.managerId);
        await m.addColumn(auditLog, auditLog.managerName);
        await m.createTable(customers);
        await m.createTable(customerAddresses);
        await m.createTable(loyaltyTransactions);
        await m.createTable(fiscalSignatures);
        await m.createTable(lanSyncPeers);
        await m.createTable(managerPins);

        // Performance indexes on high-frequency query columns.
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
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_order_items_ticket_id '
          'ON order_items (ticket_id) '
          'WHERE is_deleted = 0',
        );
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
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_audit_log_tenant_timestamp '
          'ON audit_log (tenant_id, timestamp DESC)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_license_tokens_tenant_active '
          'ON license_tokens (tenant_id, is_active)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_fiscal_signatures_receipt_id '
          'ON fiscal_signatures (receipt_id)',
        );
      }
      if (from < 8) {
        // v8: gang/wave ordering system — allows grouping items into service waves.
        await m.createTable(gangTemplates);
        await m.createTable(orderGangStates);
        await m.addColumn(products, products.defaultGangId);
        await m.addColumn(categories, categories.defaultGangId);
        await m.addColumn(orderItems, orderItems.gangId);
        await m.addColumn(kitchenTicketItems, kitchenTicketItems.gangId);
      }
      if (from < 9) {
        // v9: persist hardware terminal response fields on payments for
        // reconciliation (Wallee LTI / MyPOS Sigma).
        await m.addColumn(payments, payments.terminalTransactionId);
        await m.addColumn(payments, payments.authCode);
        await m.addColumn(payments, payments.maskedPan);
        await m.addColumn(payments, payments.cardType);
        await m.addColumn(payments, payments.entryMethod);
        await m.addColumn(payments, payments.terminalId);
        await m.addColumn(payments, payments.terminalProvider);
      }
      if (from < 10) {
        // v10: kitchen stations — configurable station list backing the KDS
        // station filter and the Products.printerGroup routing.
        await m.createTable(stations);
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
