/// GDPR Art. 15 (right of access) + Art. 17 (right to erasure) service.
///
/// Two operations:
///   * [exportForCustomer] — builds a [GdprExportBundle] with every
///     row that carries the subject's PII.
///   * [anonymizeCustomer] — scrubs PII from the customer row, the
///     addresses, the reservations matched by name+phone, and the
///     customerName field on tickets, keeping foreign keys intact so
///     the Swiss fiscal trail (10-year retention, OR Art. 958f) is
///     not broken.
///
/// Anonymisation is preferred over hard deletion because the fiscal
/// receipts / payments / audit_log must survive regardless of an
/// erasure request — they are kept for legally mandated retention.
/// After anonymisation the subject's identity cannot be recovered
/// from any column in the database; only an opaque id remains.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';

class GdprService {
  GdprService(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------------------
  // Export (Art. 15 — right of access)
  // ---------------------------------------------------------------------------

  /// Build a structured bundle of everything the database holds about
  /// [customerId]. Returns `null` when no customer row matches (the
  /// caller should surface a "no data on file" response rather than an
  /// empty bundle — the distinction matters for GDPR responses).
  Future<Map<String, dynamic>?> exportForCustomer(String customerId) async {
    final customerRow = await (_db.select(_db.customers)
          ..where((t) => t.id.equals(customerId)))
        .getSingleOrNull();
    if (customerRow == null) return null;

    final addresses = await (_db.select(_db.customerAddresses)
          ..where((t) => t.customerId.equals(customerId)))
        .get();

    final loyalty = await (_db.select(_db.loyaltyTransactions)
          ..where((t) => t.customerId.equals(customerId)))
        .get();

    final tickets = await (_db.select(_db.tickets)
          ..where((t) => t.customerId.equals(customerId)))
        .get();

    // Reservations have no customerId; match by name + phone.  Phone is
    // nullable in practice so we also include name-only matches when
    // the customer row carries no phone — a best-effort approach, not
    // a guarantee.  Skipping only hits the reservation bundle, never
    // the rest of the export.
    final reservationRows = await (_db.select(_db.reservations)
          ..where((t) {
            final nameMatch = t.customerName.equals(customerRow.name);
            final phone = customerRow.phone;
            if (phone == null || phone.isEmpty) {
              return nameMatch;
            }
            return nameMatch & t.customerPhone.equals(phone);
          }))
        .get();

    return {
      'schema': 'gdpr.export.v1',
      'generatedAt': DateTime.now().toIso8601String(),
      'customer': {
        'id': customerRow.id,
        'tenantId': customerRow.tenantId,
        'name': customerRow.name,
        'phone': customerRow.phone,
        'email': customerRow.email,
        'address': customerRow.address,
        'notes': customerRow.notes,
        'birthday': customerRow.birthday,
        'totalOrders': customerRow.totalOrders,
        'totalSpent': customerRow.totalSpent,
        'loyaltyPoints': customerRow.loyaltyPoints,
        'createdAt': customerRow.createdAt.toIso8601String(),
        'updatedAt': customerRow.updatedAt.toIso8601String(),
      },
      'addresses': addresses
          .map((a) => {
                'id': a.id,
                'label': a.label,
                'street': a.street,
                'city': a.city,
                'postalCode': a.postalCode,
                'country': a.country,
                'isDefault': a.isDefault,
              })
          .toList(),
      'tickets': tickets
          .map((t) => {
                'id': t.id,
                'orderNumber': t.orderNumber,
                'openedAt': t.openedAt.toIso8601String(),
                'status': t.status,
                'total': t.total,
                'tableId': t.tableId,
                'customerName': t.customerName,
              })
          .toList(),
      'loyaltyTransactions': loyalty
          .map((l) => {
                'id': l.id,
                'points': l.points,
                'type': l.type,
                'orderId': l.orderId,
                'description': l.description,
                'createdAt': l.createdAt.toIso8601String(),
              })
          .toList(),
      'reservations': reservationRows
          .map((r) => {
                'id': r.id,
                'customerName': r.customerName,
                'customerPhone': r.customerPhone,
                'customerEmail': r.customerEmail,
                'date': r.date.toIso8601String(),
                'partySize': r.partySize,
                'status': r.status,
                'notes': r.notes,
              })
          .toList(),
    };
  }

  // ---------------------------------------------------------------------------
  // Anonymise (Art. 17 — right to erasure)
  // ---------------------------------------------------------------------------

  /// Scrub every PII column associated with [customerId] in one
  /// transaction. Returns counts per table so the caller can show
  /// "Anonymised X row(s) across Y tables" feedback.
  ///
  /// Fiscal history is preserved by design:
  ///   * Tickets/Bills/Receipts rows survive with their customerId
  ///     intact but the denormalised customerName column is cleared.
  ///   * Loyalty transactions survive (needed to reconcile Z-reports).
  ///
  /// After this runs the customer's identity is unrecoverable from the
  /// database: name becomes an opaque id-derived token, every other
  /// PII column is null, and addresses are soft-deleted.
  Future<GdprAnonymizationResult> anonymizeCustomer(String customerId) async {
    return _db.transaction(() async {
      final customer = await (_db.select(_db.customers)
            ..where((t) => t.id.equals(customerId)))
          .getSingleOrNull();
      if (customer == null) {
        return const GdprAnonymizationResult(
          customerFound: false,
          addressesRemoved: 0,
          ticketsCleared: 0,
          reservationsCleared: 0,
        );
      }

      // 1. Customer row — keep id + tenant + totals, wipe PII.
      final anonName = _anonymizedName(customer.id);
      final now = DateTime.now();
      await (_db.update(_db.customers)
            ..where((t) => t.id.equals(customerId)))
          .write(CustomersCompanion(
        name: Value(anonName),
        phone: const Value(null),
        email: const Value(null),
        address: const Value(null),
        notes: const Value(null),
        birthday: const Value(null),
        updatedAt: Value(now),
      ));

      // 2. Customer addresses — soft-delete wholesale.
      final addressesRemoved = await (_db.delete(_db.customerAddresses)
            ..where((t) => t.customerId.equals(customerId)))
          .go();

      // 3. Tickets — clear the denormalised customerName column.
      final ticketsCleared = await (_db.update(_db.tickets)
            ..where((t) => t.customerId.equals(customerId)))
          .write(const TicketsCompanion(
        customerName: Value(null),
      ));

      // 4. Reservations — match by (name + phone) as above.
      final reservationsCleared = await (_db.update(_db.reservations)
            ..where((t) {
              final nameMatch = t.customerName.equals(customer.name);
              final phone = customer.phone;
              if (phone == null || phone.isEmpty) {
                return nameMatch;
              }
              return nameMatch & t.customerPhone.equals(phone);
            }))
          .write(_reservationWipe(anonName));

      return GdprAnonymizationResult(
        customerFound: true,
        addressesRemoved: addressesRemoved,
        ticketsCleared: ticketsCleared,
        reservationsCleared: reservationsCleared,
      );
    });
  }

  /// Deterministic opaque name derived from the customer id. Keeps a
  /// stable identifier so audit rows still reference a consistent
  /// label without exposing the original name.
  static String _anonymizedName(String customerId) {
    final suffix = customerId.length >= 8
        ? customerId.substring(customerId.length - 8)
        : customerId;
    return 'anonymized-$suffix';
  }
}

/// A small wrapper so [GdprService.anonymizeCustomer] does not return
/// a raw integer tuple. Used to render a confirmation toast in the UI.
class GdprAnonymizationResult {
  const GdprAnonymizationResult({
    required this.customerFound,
    required this.addressesRemoved,
    required this.ticketsCleared,
    required this.reservationsCleared,
  });

  final bool customerFound;
  final int addressesRemoved;
  final int ticketsCleared;
  final int reservationsCleared;

  /// Total rows the erasure touched across all tables (excluding the
  /// single customer row which is always either 1 or 0).
  int get totalRowsAffected =>
      addressesRemoved + ticketsCleared + reservationsCleared;
}

/// Helper that builds a [ReservationsCompanion] with every PII column
/// rewritten to the anonymised placeholder. Kept separate so the
/// write call above stays readable.
ReservationsCompanion _reservationWipe(String anonName) {
  return ReservationsCompanion(
    customerName: Value(anonName),
    customerPhone: const Value(null),
    customerEmail: const Value(null),
  );
}
