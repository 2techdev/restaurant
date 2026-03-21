/// Orders endpoint methods.
library;

import 'package:gastrocore_models/gastrocore_models.dart';
import '../client/gastrocore_client.dart';

class OrdersEndpoint {
  final GastrocoreClient _client;

  const OrdersEndpoint(this._client);

  // ---------------------------------------------------------------------------
  // Tickets
  // ---------------------------------------------------------------------------

  Future<List<TicketEntity>> getOpenTickets(String tenantId) async {
    final list = await _client.getList(
      '/api/v1/orders/tickets',
      queryParams: {'tenant_id': tenantId, 'status': 'open'},
    );
    return list
        .map((j) => TicketEntity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<TicketEntity>> getTickets(
    String tenantId, {
    String? status,
    DateTime? from,
    DateTime? to,
    int? limit,
    int? offset,
  }) async {
    final params = <String, String>{'tenant_id': tenantId};
    if (status != null) params['status'] = status;
    if (from != null) params['from'] = from.toIso8601String();
    if (to != null) params['to'] = to.toIso8601String();
    if (limit != null) params['limit'] = limit.toString();
    if (offset != null) params['offset'] = offset.toString();

    final list = await _client.getList(
      '/api/v1/orders/tickets',
      queryParams: params,
    );
    return list
        .map((j) => TicketEntity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<TicketEntity> getTicket(String ticketId) async {
    final json = await _client.get('/api/v1/orders/tickets/$ticketId');
    return TicketEntity.fromJson(json);
  }

  Future<TicketEntity> createTicket(TicketEntity ticket) async {
    final json = await _client.post(
      '/api/v1/orders/tickets',
      ticket.toJson(),
    );
    return TicketEntity.fromJson(json);
  }

  Future<TicketEntity> updateTicket(TicketEntity ticket) async {
    final json = await _client.put(
      '/api/v1/orders/tickets/${ticket.id}',
      ticket.toJson(),
    );
    return TicketEntity.fromJson(json);
  }

  Future<TicketEntity> updateTicketStatus(
    String ticketId,
    TicketStatus status,
  ) async {
    final json = await _client.patch(
      '/api/v1/orders/tickets/$ticketId/status',
      {'status': status.name},
    );
    return TicketEntity.fromJson(json);
  }

  Future<TicketEntity> sendToKitchen(String ticketId) async {
    final json = await _client.post(
      '/api/v1/orders/tickets/$ticketId/send',
      {},
    );
    return TicketEntity.fromJson(json);
  }

  Future<TicketEntity> voidTicket(
    String ticketId, {
    required String reason,
    required String authorizedBy,
  }) async {
    final json = await _client.post(
      '/api/v1/orders/tickets/$ticketId/void',
      {'reason': reason, 'authorized_by': authorizedBy},
    );
    return TicketEntity.fromJson(json);
  }

  // ---------------------------------------------------------------------------
  // Payments
  // ---------------------------------------------------------------------------

  Future<PaymentEntity> createPayment(PaymentEntity payment) async {
    final json = await _client.post(
      '/api/v1/orders/payments',
      payment.toJson(),
    );
    return PaymentEntity.fromJson(json);
  }

  Future<List<PaymentEntity>> getPayments(String ticketId) async {
    final list = await _client.getList(
      '/api/v1/orders/tickets/$ticketId/payments',
    );
    return list
        .map((j) => PaymentEntity.fromJson(j as Map<String, dynamic>))
        .toList();
  }
}
