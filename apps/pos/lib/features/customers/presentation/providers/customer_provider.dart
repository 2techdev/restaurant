import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/customer_entity.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/customer_address_entity.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/loyalty_transaction_entity.dart';

// ── Repository ────────────────────────────────────────────────────

final customerRepositoryProvider = Provider<CustomerRepositoryImpl>((ref) {
  final db = ref.watch(databaseProvider);
  return CustomerRepositoryImpl(db);
});

// ── Search / Filter state ─────────────────────────────────────────

final customerSearchProvider = StateProvider<String>((ref) => '');
final customerTierFilterProvider = StateProvider<CustomerTier?>((ref) => null);

// ── Customer List ─────────────────────────────────────────────────

final customersProvider =
    FutureProvider<List<CustomerEntity>>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final search = ref.watch(customerSearchProvider).trim();

  if (search.isEmpty) {
    return repo.getAllCustomers(tenantId);
  }
  return repo.searchCustomers(tenantId, search);
});

/// Filtered by tier on top of search results.
final filteredCustomersProvider =
    FutureProvider<List<CustomerEntity>>((ref) async {
  final customers = await ref.watch(customersProvider.future);
  final tier = ref.watch(customerTierFilterProvider);
  if (tier == null) return customers;
  return customers.where((c) => c.tier == tier).toList();
});

// ── Single Customer ───────────────────────────────────────────────

final customerByIdProvider =
    FutureProvider.family<CustomerEntity?, String>((ref, id) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getCustomerById(id);
});

// ── Addresses ─────────────────────────────────────────────────────

final customerAddressesProvider =
    FutureProvider.family<List<CustomerAddressEntity>, String>(
  (ref, customerId) async {
    final repo = ref.watch(customerRepositoryProvider);
    return repo.getAddressesForCustomer(customerId);
  },
);

// ── Loyalty Transactions ──────────────────────────────────────────

final loyaltyTransactionsProvider =
    FutureProvider.family<List<LoyaltyTransactionEntity>, String>(
  (ref, customerId) async {
    final repo = ref.watch(customerRepositoryProvider);
    return repo.getLoyaltyTransactions(customerId);
  },
);

// ── Customer Notifier (CRUD + loyalty ops) ────────────────────────

class CustomerNotifier extends StateNotifier<AsyncValue<void>> {
  final CustomerRepositoryImpl _repo;
  final Ref _ref;

  CustomerNotifier(this._repo, this._ref) : super(const AsyncValue.data(null));

  Future<CustomerEntity?> createCustomer({
    required String tenantId,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    String? birthday,
  }) async {
    state = const AsyncValue.loading();
    try {
      final now = DateTime.now();
      final customer = CustomerEntity(
        id: IdGenerator.generateId(),
        tenantId: tenantId,
        name: name,
        phone: phone,
        email: email,
        address: address,
        notes: notes,
        birthday: birthday,
        createdAt: now,
        updatedAt: now,
      );
      final saved = await _repo.insertCustomer(customer);
      _ref.invalidate(customersProvider);
      state = const AsyncValue.data(null);
      return saved;
    } catch (e, s) {
      state = AsyncValue.error(e, s);
      return null;
    }
  }

  Future<void> updateCustomer(CustomerEntity customer) async {
    state = const AsyncValue.loading();
    try {
      await _repo.updateCustomer(customer);
      _ref.invalidate(customersProvider);
      _ref.invalidate(customerByIdProvider(customer.id));
      state = const AsyncValue.data(null);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> deleteCustomer(String id) async {
    state = const AsyncValue.loading();
    try {
      await _repo.deleteCustomer(id);
      _ref.invalidate(customersProvider);
      state = const AsyncValue.data(null);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> addAddress(CustomerAddressEntity address) async {
    try {
      await _repo.insertAddress(address);
      _ref.invalidate(customerAddressesProvider(address.customerId));
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> removeAddress(
      String addressId, String customerId) async {
    try {
      await _repo.deleteAddress(addressId);
      _ref.invalidate(customerAddressesProvider(customerId));
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> setDefaultAddress(
      String customerId, String addressId) async {
    try {
      await _repo.setDefaultAddress(customerId, addressId);
      _ref.invalidate(customerAddressesProvider(customerId));
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  /// Called when an order is completed — auto-earn points.
  Future<void> onOrderCompleted(
    String customerId, {
    required int amountCents,
  }) async {
    try {
      await _repo.recordOrderCompleted(customerId, amountCents: amountCents);
      _ref.invalidate(customerByIdProvider(customerId));
      _ref.invalidate(loyaltyTransactionsProvider(customerId));
      _ref.invalidate(customersProvider);
    } catch (_) {
      // Non-critical: loyalty failure should not block order completion
    }
  }

  /// Redeem points for a discount (returns discount in cents).
  Future<int> redeemPoints(
    String customerId, {
    required int points,
    String? orderId,
  }) async {
    try {
      final discount = await _repo.redeemPoints(
        customerId,
        points: points,
        orderId: orderId,
      );
      _ref.invalidate(customerByIdProvider(customerId));
      _ref.invalidate(loyaltyTransactionsProvider(customerId));
      _ref.invalidate(customersProvider);
      return discount;
    } catch (e, s) {
      state = AsyncValue.error(e, s);
      return 0;
    }
  }

  /// Manual points adjustment (manager).
  Future<void> adjustPoints(
    String customerId, {
    required int delta,
    required String description,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _repo.adjustPoints(customerId,
          delta: delta, description: description);
      _ref.invalidate(customerByIdProvider(customerId));
      _ref.invalidate(loyaltyTransactionsProvider(customerId));
      _ref.invalidate(customersProvider);
      state = const AsyncValue.data(null);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }
}

final customerNotifierProvider =
    StateNotifierProvider<CustomerNotifier, AsyncValue<void>>((ref) {
  final repo = ref.watch(customerRepositoryProvider);
  return CustomerNotifier(repo, ref);
});

/// Customers with a birthday in the next 7 days (for dashboard reminders).
final birthdayRemindersProvider =
    FutureProvider<List<CustomerEntity>>((ref) async {
  final customers = await ref.watch(customersProvider.future);
  return customers.where((c) => c.hasBirthdayThisWeek).toList();
});
