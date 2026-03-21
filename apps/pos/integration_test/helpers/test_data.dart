/// Seed-data builders for GastroCore POS integration tests.
///
/// These helpers insert rows directly into [testDb] so that tests can set up
/// specific preconditions (e.g. a ticket that is ready for payment) without
/// going through the full UI flow every time.
///
/// All helpers are async and return the created entity id so callers can
/// reference it in subsequent steps.
library;

import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/payments/data/repositories/payment_repository_impl.dart';
import 'package:gastrocore_pos/features/payments/domain/entities/payment_entity.dart';
import 'package:gastrocore_pos/features/shifts/data/repositories/shift_repository_impl.dart';

import 'test_app.dart' show testDb, testTenantId;

// ---------------------------------------------------------------------------
// Default product names used by seed data / demo data
// ---------------------------------------------------------------------------

const kSeedProductNames = [
  'Adana Kebap',
  'Karisik Izgara',
  'Iskender',
  'Margherita',
  'Caesar Salata',
  'Mercimek Corbasi',
];

// ---------------------------------------------------------------------------
// Shift helpers
// ---------------------------------------------------------------------------

/// Open a fresh shift and return its id.
Future<String> seedOpenShift({
  String? userId,
  int openingCash = 50000, // CHF 500.00
}) async {
  final repo = ShiftRepositoryImpl(testDb);

  // Find a user if none supplied.
  final resolvedUserId = userId ?? await _anyUserId();

  final shift = await repo.openShift(
    tenantId: testTenantId,
    userId: resolvedUserId,
    deviceId: 'DEV-TEST-01',
    openingCash: openingCash,
  );
  return shift.id;
}

/// Close the shift with [shiftId] and return the updated shift.
Future<void> seedCloseShift(String shiftId, {int closingCash = 50000}) async {
  final repo = ShiftRepositoryImpl(testDb);
  await repo.closeShift(shiftId: shiftId, closingCash: closingCash);
}

// ---------------------------------------------------------------------------
// Ticket helpers
// ---------------------------------------------------------------------------

/// Create a draft ticket with [itemCount] items and return the ticket id.
Future<String> seedTicketWithItems({
  int itemCount = 2,
  OrderType orderType = OrderType.dineIn,
  int unitPrice = 2500, // CHF 25.00
}) async {
  final repo = OrderRepositoryImpl(testDb);

  final ticketId = IdGenerator.generateId();
  final items = List.generate(itemCount, (i) {
    final itemId = IdGenerator.generateId();
    return OrderItemEntity(
      id: itemId,
      tenantId: testTenantId,
      ticketId: ticketId,
      productId: 'prod-seed-$i',
      productName: kSeedProductNames[i % kSeedProductNames.length],
      quantity: 1,
      unitPrice: unitPrice,
      subtotal: unitPrice,
      taxGroup: 'food',
    );
  });

  final ticket = TicketEntity(
    id: ticketId,
    tenantId: testTenantId,
    orderNumber: _nextOrderNumber(),
    orderType: orderType,
    status: TicketStatus.draft,
    openedAt: DateTime.now(),
    deviceId: 'DEV-TEST-01',
    items: items,
  );

  await repo.createTicket(ticket);
  return ticketId;
}

/// Create an open (sent-to-kitchen) ticket and return its id.
Future<String> seedOpenTicket() async {
  final ticketId = await seedTicketWithItems();
  final repo = OrderRepositoryImpl(testDb);
  await repo.updateTicketStatus(ticketId, TicketStatus.sent);
  return ticketId;
}

// ---------------------------------------------------------------------------
// Payment helpers
// ---------------------------------------------------------------------------

/// Fully pay a ticket with cash and return the payment id.
Future<String> seedCashPayment(String ticketId, {int amount = 5000}) async {
  final repo = PaymentRepositoryImpl(testDb);
  final payment = await repo.processPayment(
    ticketId: ticketId,
    tenantId: testTenantId,
    paymentMethod: PaymentMethod.cash,
    amount: amount,
    tenderedAmount: amount + 500, // a bit extra to test change calculation
    receivedBy: await _anyUserId(),
  );
  return payment.id;
}

// ---------------------------------------------------------------------------
// Private utilities
// ---------------------------------------------------------------------------

int _orderCounter = 1000;

String _nextOrderNumber() => (_orderCounter++).toString().padLeft(4, '0');

Future<String> _anyUserId() async {
  final users = await testDb.select(testDb.users).get();
  if (users.isEmpty) {
    throw StateError(
        'No users in test database — did AppInitializer.initialize() run?');
  }
  return users.first.id;
}
