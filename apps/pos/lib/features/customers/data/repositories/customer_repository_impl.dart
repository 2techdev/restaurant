import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/customer_entity.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/customer_address_entity.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/loyalty_transaction_entity.dart';

class CustomerRepositoryImpl {
  final AppDatabase _db;

  CustomerRepositoryImpl(this._db);

  // ── Customers ─────────────────────────────────────────────────

  Future<List<CustomerEntity>> getAllCustomers(String tenantId) async {
    final rows = await (_db.select(_db.customers)
          ..where((c) => c.tenantId.equals(tenantId) & c.isDeleted.equals(false))
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .get();
    return rows.map(_rowToEntity).toList();
  }

  Future<List<CustomerEntity>> searchCustomers(
    String tenantId,
    String query,
  ) async {
    final q = '%${query.toLowerCase()}%';
    final rows = await (_db.select(_db.customers)
          ..where(
            (c) =>
                c.tenantId.equals(tenantId) &
                c.isDeleted.equals(false) &
                (c.name.lower().like(q) |
                    c.phone.lower().like(q) |
                    c.email.lower().like(q)),
          )
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .get();
    return rows.map(_rowToEntity).toList();
  }

  Future<CustomerEntity?> getCustomerById(String id) async {
    final row = await (_db.select(_db.customers)
          ..where((c) => c.id.equals(id) & c.isDeleted.equals(false)))
        .getSingleOrNull();
    return row == null ? null : _rowToEntity(row);
  }

  Future<CustomerEntity?> getCustomerByPhone(
      String tenantId, String phone) async {
    final row = await (_db.select(_db.customers)
          ..where(
            (c) =>
                c.tenantId.equals(tenantId) &
                c.phone.equals(phone) &
                c.isDeleted.equals(false),
          ))
        .getSingleOrNull();
    return row == null ? null : _rowToEntity(row);
  }

  Future<CustomerEntity> insertCustomer(CustomerEntity customer) async {
    final now = DateTime.now();
    final companion = CustomersCompanion.insert(
      id: customer.id,
      tenantId: customer.tenantId,
      name: customer.name,
      phone: Value(customer.phone),
      email: Value(customer.email),
      address: Value(customer.address),
      notes: Value(customer.notes),
      birthday: Value(customer.birthday),
      createdAt: now,
      updatedAt: now,
      totalOrders: const Value(0),
      totalSpent: const Value(0),
      loyaltyPoints: const Value(0),
    );
    await _db.into(_db.customers).insert(companion);
    return customer.copyWith(updatedAt: now);
  }

  Future<void> updateCustomer(CustomerEntity customer) async {
    final now = DateTime.now();
    await (_db.update(_db.customers)..where((c) => c.id.equals(customer.id)))
        .write(CustomersCompanion(
      name: Value(customer.name),
      phone: Value(customer.phone),
      email: Value(customer.email),
      address: Value(customer.address),
      notes: Value(customer.notes),
      birthday: Value(customer.birthday),
      updatedAt: Value(now),
    ));
  }

  Future<void> deleteCustomer(String id) async {
    await (_db.update(_db.customers)..where((c) => c.id.equals(id)))
        .write(CustomersCompanion(
      isDeleted: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Increment order count and total spent after completing an order.
  Future<void> recordOrderCompleted(
    String customerId, {
    required int amountCents,
  }) async {
    final customer = await getCustomerById(customerId);
    if (customer == null) return;

    final pointsEarned = amountCents ~/ 100; // 1 CHF = 1 point

    await (_db.update(_db.customers)..where((c) => c.id.equals(customerId)))
        .write(CustomersCompanion(
      totalOrders: Value(customer.totalOrders + 1),
      totalSpent: Value(customer.totalSpent + amountCents),
      loyaltyPoints: Value(customer.loyaltyPoints + pointsEarned),
      updatedAt: Value(DateTime.now()),
    ));

    // Record loyalty transaction
    await _insertLoyaltyTransaction(LoyaltyTransactionEntity(
      id: IdGenerator.generateId(),
      customerId: customerId,
      points: pointsEarned,
      type: LoyaltyTransactionType.earn,
      description: 'Order completed',
      createdAt: DateTime.now(),
    ));
  }

  /// Redeem loyalty points (100 points = CHF 1.00 discount).
  Future<int> redeemPoints(
    String customerId, {
    required int points,
    String? orderId,
  }) async {
    final customer = await getCustomerById(customerId);
    if (customer == null) throw Exception('Customer not found');
    if (customer.loyaltyPoints < points) {
      throw Exception('Insufficient points');
    }

    await (_db.update(_db.customers)..where((c) => c.id.equals(customerId)))
        .write(CustomersCompanion(
      loyaltyPoints: Value(customer.loyaltyPoints - points),
      updatedAt: Value(DateTime.now()),
    ));

    await _insertLoyaltyTransaction(LoyaltyTransactionEntity(
      id: IdGenerator.generateId(),
      customerId: customerId,
      points: -points,
      type: LoyaltyTransactionType.redeem,
      orderId: orderId,
      description: 'Points redeemed',
      createdAt: DateTime.now(),
    ));

    // Return discount in cents (100 points = 100 cents = CHF 1.00)
    return points;
  }

  // ── Customer Addresses ────────────────────────────────────────

  Future<List<CustomerAddressEntity>> getAddressesForCustomer(
      String customerId) async {
    final rows = await (_db.select(_db.customerAddresses)
          ..where((a) => a.customerId.equals(customerId))
          ..orderBy([
            (a) => OrderingTerm.desc(a.isDefault),
            (a) => OrderingTerm.asc(a.createdAt),
          ]))
        .get();
    return rows.map(_addressRowToEntity).toList();
  }

  Future<void> insertAddress(CustomerAddressEntity address) async {
    if (address.isDefault) {
      await _clearDefaultAddress(address.customerId);
    }
    await _db.into(_db.customerAddresses).insert(
          CustomerAddressesCompanion.insert(
            id: address.id,
            customerId: address.customerId,
            label: Value(address.label),
            street: address.street,
            city: address.city,
            postalCode: address.postalCode,
            country: Value(address.country),
            isDefault: Value(address.isDefault),
            createdAt: address.createdAt,
          ),
        );
  }

  Future<void> deleteAddress(String id) async {
    await (_db.delete(_db.customerAddresses)..where((a) => a.id.equals(id)))
        .go();
  }

  Future<void> setDefaultAddress(String customerId, String addressId) async {
    await _clearDefaultAddress(customerId);
    await (_db.update(_db.customerAddresses)
          ..where((a) => a.id.equals(addressId)))
        .write(const CustomerAddressesCompanion(isDefault: Value(true)));
  }

  Future<void> _clearDefaultAddress(String customerId) async {
    await (_db.update(_db.customerAddresses)
          ..where((a) =>
              a.customerId.equals(customerId) & a.isDefault.equals(true)))
        .write(const CustomerAddressesCompanion(isDefault: Value(false)));
  }

  // ── Loyalty Transactions ──────────────────────────────────────

  Future<List<LoyaltyTransactionEntity>> getLoyaltyTransactions(
    String customerId, {
    int limit = 50,
  }) async {
    final rows = await (_db.select(_db.loyaltyTransactions)
          ..where((t) => t.customerId.equals(customerId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
    return rows.map(_loyaltyRowToEntity).toList();
  }

  Future<void> _insertLoyaltyTransaction(
      LoyaltyTransactionEntity tx) async {
    await _db.into(_db.loyaltyTransactions).insert(
          LoyaltyTransactionsCompanion.insert(
            id: tx.id,
            customerId: tx.customerId,
            points: tx.points,
            type: tx.type.name,
            orderId: Value(tx.orderId),
            description: Value(tx.description),
            createdAt: tx.createdAt,
          ),
        );
  }

  /// Manually adjust loyalty points (manager action).
  Future<void> adjustPoints(
    String customerId, {
    required int delta,
    required String description,
  }) async {
    final customer = await getCustomerById(customerId);
    if (customer == null) throw Exception('Customer not found');

    final newPoints = (customer.loyaltyPoints + delta).clamp(0, 999999);
    await (_db.update(_db.customers)..where((c) => c.id.equals(customerId)))
        .write(CustomersCompanion(
      loyaltyPoints: Value(newPoints),
      updatedAt: Value(DateTime.now()),
    ));

    await _insertLoyaltyTransaction(LoyaltyTransactionEntity(
      id: IdGenerator.generateId(),
      customerId: customerId,
      points: delta,
      type: LoyaltyTransactionType.adjust,
      description: description,
      createdAt: DateTime.now(),
    ));
  }

  // ── Mappers ──────────────────────────────────────────────────

  CustomerEntity _rowToEntity(CustomerRow row) => CustomerEntity(
        id: row.id,
        tenantId: row.tenantId,
        name: row.name,
        phone: row.phone,
        email: row.email,
        address: row.address,
        notes: row.notes,
        birthday: row.birthday,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        totalOrders: row.totalOrders,
        totalSpent: row.totalSpent,
        loyaltyPoints: row.loyaltyPoints,
      );

  CustomerAddressEntity _addressRowToEntity(CustomerAddressRow row) =>
      CustomerAddressEntity(
        id: row.id,
        customerId: row.customerId,
        label: row.label,
        street: row.street,
        city: row.city,
        postalCode: row.postalCode,
        country: row.country,
        isDefault: row.isDefault,
        createdAt: row.createdAt,
      );

  LoyaltyTransactionEntity _loyaltyRowToEntity(LoyaltyTransactionRow row) =>
      LoyaltyTransactionEntity(
        id: row.id,
        customerId: row.customerId,
        points: row.points,
        type: LoyaltyTransactionType.values.firstWhere(
          (t) => t.name == row.type,
          orElse: () => LoyaltyTransactionType.adjust,
        ),
        orderId: row.orderId,
        description: row.description,
        createdAt: row.createdAt,
      );
}
