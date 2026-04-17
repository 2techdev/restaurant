/// Payment endpoints — tenant payment methods and transactions.
library;

import 'package:gastrocore_models/gastrocore_models.dart';

import '../client/gastrocore_client.dart';

class PaymentEndpoint {
  final GastrocoreClient _client;

  const PaymentEndpoint(this._client);

  // ---------------------------------------------------------------------------
  // Payment methods (catalog)
  // ---------------------------------------------------------------------------

  Future<List<PaymentMethodEntity>> listMethods(String tenantId) async {
    final list = await _client.getList(
      '/api/v1/payments/methods',
      queryParams: {'tenant_id': tenantId},
    );
    return list
        .map((j) =>
            PaymentMethodEntity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<PaymentMethodEntity> createMethod(PaymentMethodEntity method) async {
    final json =
        await _client.post('/api/v1/payments/methods', method.toJson());
    return PaymentMethodEntity.fromJson(json);
  }

  Future<PaymentMethodEntity> updateMethod(PaymentMethodEntity method) async {
    final json = await _client.put(
      '/api/v1/payments/methods/${method.id}',
      method.toJson(),
    );
    return PaymentMethodEntity.fromJson(json);
  }

  Future<void> deleteMethod(String methodId) {
    return _client.delete('/api/v1/payments/methods/$methodId');
  }

  // ---------------------------------------------------------------------------
  // Transactions (PaymentEntity) and bills
  // ---------------------------------------------------------------------------

  Future<BillEntity> getBill(String billId) async {
    final json = await _client.get('/api/v1/payments/bills/$billId');
    return BillEntity.fromJson(json);
  }

  Future<BillEntity> openBill({
    required String tenantId,
    required String ticketId,
  }) async {
    final json = await _client.post('/api/v1/payments/bills', {
      'tenant_id': tenantId,
      'ticket_id': ticketId,
    });
    return BillEntity.fromJson(json);
  }

  /// Record a payment transaction against an open bill.
  Future<PaymentEntity> recordPayment(PaymentEntity payment) async {
    final json = await _client.post(
      '/api/v1/payments/bills/${payment.billId}/payments',
      payment.toJson(),
    );
    return PaymentEntity.fromJson(json);
  }

  Future<BillEntity> voidBill(String billId, {String? reason}) async {
    final json = await _client.post('/api/v1/payments/bills/$billId/void', {
      if (reason != null) 'reason': reason,
    });
    return BillEntity.fromJson(json);
  }

  /// Refund a prior payment (partial refunds supported via [amount]).
  Future<PaymentEntity> refundPayment({
    required String paymentId,
    required int amount,
    String? reason,
  }) async {
    final json = await _client.post(
      '/api/v1/payments/$paymentId/refund',
      {
        'amount': amount,
        if (reason != null) 'reason': reason,
      },
    );
    return PaymentEntity.fromJson(json);
  }
}
