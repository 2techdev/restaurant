import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:gastrocore_pos/features/audit_log/data/daos/audit_log_dao.dart';
import 'package:gastrocore_pos/features/inventory/data/daos/inventory_dao.dart';
import 'package:gastrocore_pos/features/menu/data/daos/combo_dao.dart';
import 'package:gastrocore_pos/features/payments/data/daos/receipt_counter_dao.dart';
import 'package:gastrocore_pos/features/sync/data/daos/sync_event_dao.dart';

import 'tables/action_buttons.dart';
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
import 'tables/receipt_counters.dart';
import 'tables/receipts.dart';
import 'tables/restaurant_tables.dart';
import 'tables/shifts.dart';
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
import 'tables/receipt_templates.dart';
import 'tables/user_tenant_assignments.dart';
import 'tables/z_reports.dart';

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
    ReceiptCounters,
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
    ActionButtons,
    ReceiptTemplates,
    UserTenantAssignments,
    ZReports,
  ],
  daos: [AuditLogDao, ComboDao, InventoryDao, ReceiptCounterDao, SyncEventDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 23;

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
        // v9: first-class seat number on order items for seat-based split.
        await m.addColumn(orderItems, orderItems.seatNumber);
      }
      if (from < 10) {
        // v10: orthogonal state flags on restaurant tables so one tile can
        // be `occupied` AND `billRequested` AND `vip` simultaneously.
        await m.addColumn(restaurantTables, restaurantTables.flags);
      }
      if (from < 11) {
        // v11: Order Tag Group richness — SambaPOS parity parameters on
        // modifier groups (askQuantity, freeTagging, columnCount, prefix).
        await m.addColumn(modifierGroups, modifierGroups.askQuantity);
        await m.addColumn(modifierGroups, modifierGroups.freeTagging);
        await m.addColumn(modifierGroups, modifierGroups.columnCount);
        await m.addColumn(modifierGroups, modifierGroups.prefix);
      }
      if (from < 12) {
        // v12: per-application Order Tag richness — quantity multiplier
        // (askQuantity) and free-form note (freeTagging) on each applied
        // modifier. Additive & non-breaking: existing rows default to
        // quantity=1, note=NULL.
        await m.addColumn(orderItemModifiers, orderItemModifiers.quantity);
        await m.addColumn(orderItemModifiers, orderItemModifiers.note);
      }
      if (from < 13) {
        // v13: SambaPOS-style user-defined function buttons. Operators can
        // configure labelled buttons that fire actions (discount, gift, note,
        // course change, print) against the active ticket.
        await m.createTable(actionButtons);
      }
      if (from < 14) {
        // v14: sealed, sequence-numbered Z-reports — sealed snapshots that
        // back the Swiss daily-close requirement so a given day's totals
        // can be reproduced even after downstream data edits.
        await m.createTable(zReports);
      }
      if (from < 15) {
        // v15: sold-out / 86'd flag on products. Operators can toggle a
        // product "satışta değil" without delisting it — POS greys the
        // tile out and blocks taps until the product is re-opened.
        // Default true so every existing row stays sellable.
        await m.addColumn(products, products.isAvailable);
      }
      if (from < 16) {
        // v16: nullable customer_id FK on tickets. Lets the POS topbar
        // attach a loyalty account to an open ticket so the payment
        // screen can surface puan balance and redemption. Existing
        // rows stay null (walk-in orders) — additive, non-breaking.
        await m.addColumn(tickets, tickets.customerId);
      }
      if (from < 17) {
        // v17: per-tenant atomic receipt counter + UNIQUE index on
        // receipts(tenant_id, receipt_number). Swiss fiscal audit rules
        // forbid duplicate receipt numbers; the counter table lets the
        // DAO increment inside a transaction and the partial-unique
        // index is a last-resort guardrail if something bypasses the
        // DAO. Existing rows stay intact — additive.
        await m.createTable(receiptCounters);
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_receipts_tenant_number '
          'ON receipts (tenant_id, receipt_number) '
          'WHERE is_deleted = 0',
        );
      }
      if (from < 18) {
        // v18: combo/set-menu flag + optional bundle discount on Products.
        // The combo_items table already exists (added earlier) but was
        // orphaned — no flag on Products identified which rows actually
        // bundle sub-items. These two columns wire the scaffolding up.
        await m.addColumn(products, products.isCombo);
        await m.addColumn(products, products.comboDiscountCents);
      }
      if (from < 19) {
        // v19 (M4): ad-hoc table flag on RestaurantTables. Cashiers can
        // ring up "Tisch 150" from the sales-shell numpad; the row is
        // soft-deleted on close so the floor plan doesn't accumulate
        // historical strays. Existing persistent tables default to
        // false, matching the column default and pre-M4 behaviour.
        await m.addColumn(restaurantTables, restaurantTables.isTemporary);
      }
      if (from < 20) {
        // v20: cloud-master menu sync metadata. The MenuSyncService stamps
        // `cloudVersion` on every product/category row it applies, so the
        // audit trail can correlate POS state back to a published Cloud
        // version (see lib/features/menu_sync/). Null for legacy rows or
        // rows authored locally while menuEditMode != 'cloud'.
        await m.addColumn(products, products.cloudVersion);
        await m.addColumn(categories, categories.cloudVersion);
      }
      if (from < 21) {
        // v21: Swiss MWST-compliant receipt templates, replicated from
        // the backoffice via menu sync snapshots. Each template carries a
        // language + width and is consumed by the print engine at order
        // completion. UID-Nummer is rendered from the tenants row.
        await m.createTable(receiptTemplates);
      }
      if (from < 22) {
        // v22: template_type discriminator (kitchen_ticket /
        // customer_receipt / z_report). The print engine picks the right
        // builder based on this value at print time. Existing rows default
        // to customer_receipt, matching pre-22 behaviour.
        //
        // Hotfix 2026-05-07: pilot devices upgrading from schema 21 already
        // had `template_type` in the table because Drift's `m.createTable`
        // uses the LATEST Dart definition, not the schema-pinned one. So
        // the column was created in v21 and re-adding it in v22 raises
        // SqliteException "duplicate column name". Guard with a PRAGMA
        // existence check so the migration is idempotent regardless of
        // whether the prior install was 21-pristine or 21-with-22-leak.
        final hasColumn = await _columnExists('receipt_templates', 'template_type');
        if (!hasColumn) {
          await m.addColumn(receiptTemplates, receiptTemplates.templateType);
        }
      }
      if (from < 23) {
        // v23: user_tenant_assignments — N:M user↔tenant relation enabling
        // the runtime tenant switcher (operators working at multiple
        // restaurants). The schema migration runs everywhere, but the
        // switcher UI is gated by the `multiTenantSwitcherEnabled` flag in
        // AppSettings (default false), so pilot devices stay single-tenant
        // until the operator (or remote config) opts in. Existing tickets
        // / users are not touched — additive only.
        await m.createTable(userTenantAssignments);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_user_tenant_user '
          'ON user_tenant_assignments (user_id) '
          'WHERE is_deleted = 0',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_user_tenant_pair '
          'ON user_tenant_assignments (user_id, tenant_id) '
          'WHERE is_deleted = 0',
        );
      }
    },
    onCreate: (m) async {
      await m.createAll();
    },
  );

  /// Returns true if [table] already has a column named [column] in the
  /// live SQLite schema. Used to make ALTER TABLE migrations idempotent
  /// across installs that may have been affected by Drift's createTable
  /// pulling forward future column definitions.
  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect(
      "PRAGMA table_info('$table')",
    ).get();
    return rows.any((r) => r.read<String>('name') == column);
  }

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
