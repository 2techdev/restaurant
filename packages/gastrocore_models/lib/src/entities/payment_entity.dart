/// Payment and bill entities.
library;

/// Accepted payment methods.
enum PaymentMethod {
  cash,
  creditCard,
  debitCard,
  other,
}

/// Lifecycle status of a bill.
enum BillStatus {
  open,
  partiallyPaid,
  fullyPaid,
  voidStatus,
}

/// A single payment transaction against a bill.
class PaymentEntity {
  final String id;
  final String tenantId;
  final String billId;
  final String ticketId;
  final PaymentMethod paymentMethod;
  final int amount;
  final int tipAmount;
  final int tenderedAmount;
  final int changeAmount;
  final String? reference;
  final String receivedBy;
  final DateTime paidAt;
  final String? paySubChannel;
  final String? paymentForm;
  final String? paymentReference;
  final String? externalChannel;
  final String? externalPaymentId;
  final String? cashierName;

  const PaymentEntity({
    required this.id,
    required this.tenantId,
    required this.billId,
    required this.ticketId,
    required this.paymentMethod,
    required this.amount,
    this.tipAmount = 0,
    this.tenderedAmount = 0,
    this.changeAmount = 0,
    this.reference,
    required this.receivedBy,
    required this.paidAt,
    this.paySubChannel,
    this.paymentForm,
    this.paymentReference,
    this.externalChannel,
    this.externalPaymentId,
    this.cashierName,
  });

  factory PaymentEntity.fromJson(Map<String, dynamic> json) => PaymentEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        billId: json['bill_id'] as String,
        ticketId: json['ticket_id'] as String,
        paymentMethod: PaymentMethod.values.firstWhere(
          (e) => e.name == json['payment_method'],
          orElse: () => PaymentMethod.cash,
        ),
        amount: (json['amount'] as num).toInt(),
        tipAmount: (json['tip_amount'] as num?)?.toInt() ?? 0,
        tenderedAmount: (json['tendered_amount'] as num?)?.toInt() ?? 0,
        changeAmount: (json['change_amount'] as num?)?.toInt() ?? 0,
        reference: json['reference'] as String?,
        receivedBy: json['received_by'] as String,
        paidAt: DateTime.parse(json['paid_at'] as String),
        paySubChannel: json['pay_sub_channel'] as String?,
        paymentForm: json['payment_form'] as String?,
        paymentReference: json['payment_reference'] as String?,
        externalChannel: json['external_channel'] as String?,
        externalPaymentId: json['external_payment_id'] as String?,
        cashierName: json['cashier_name'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'bill_id': billId,
        'ticket_id': ticketId,
        'payment_method': paymentMethod.name,
        'amount': amount,
        'tip_amount': tipAmount,
        'tendered_amount': tenderedAmount,
        'change_amount': changeAmount,
        if (reference != null) 'reference': reference,
        'received_by': receivedBy,
        'paid_at': paidAt.toIso8601String(),
        if (paySubChannel != null) 'pay_sub_channel': paySubChannel,
        if (paymentForm != null) 'payment_form': paymentForm,
        if (paymentReference != null) 'payment_reference': paymentReference,
        if (externalChannel != null) 'external_channel': externalChannel,
        if (externalPaymentId != null)
          'external_payment_id': externalPaymentId,
        if (cashierName != null) 'cashier_name': cashierName,
      };

  PaymentEntity copyWith({
    String? id,
    String? tenantId,
    String? billId,
    String? ticketId,
    PaymentMethod? paymentMethod,
    int? amount,
    int? tipAmount,
    int? tenderedAmount,
    int? changeAmount,
    String? Function()? reference,
    String? receivedBy,
    DateTime? paidAt,
    String? Function()? paySubChannel,
    String? Function()? paymentForm,
    String? Function()? paymentReference,
    String? Function()? externalChannel,
    String? Function()? externalPaymentId,
    String? Function()? cashierName,
  }) {
    return PaymentEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      billId: billId ?? this.billId,
      ticketId: ticketId ?? this.ticketId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      amount: amount ?? this.amount,
      tipAmount: tipAmount ?? this.tipAmount,
      tenderedAmount: tenderedAmount ?? this.tenderedAmount,
      changeAmount: changeAmount ?? this.changeAmount,
      reference: reference != null ? reference() : this.reference,
      receivedBy: receivedBy ?? this.receivedBy,
      paidAt: paidAt ?? this.paidAt,
      paySubChannel:
          paySubChannel != null ? paySubChannel() : this.paySubChannel,
      paymentForm: paymentForm != null ? paymentForm() : this.paymentForm,
      paymentReference:
          paymentReference != null ? paymentReference() : this.paymentReference,
      externalChannel:
          externalChannel != null ? externalChannel() : this.externalChannel,
      externalPaymentId: externalPaymentId != null
          ? externalPaymentId()
          : this.externalPaymentId,
      cashierName: cashierName != null ? cashierName() : this.cashierName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          billId == other.billId &&
          ticketId == other.ticketId &&
          paymentMethod == other.paymentMethod &&
          amount == other.amount;

  @override
  int get hashCode =>
      Object.hash(id, tenantId, billId, ticketId, paymentMethod, amount);

  @override
  String toString() =>
      'PaymentEntity(id: $id, method: ${paymentMethod.name}, amount: $amount)';
}

/// Financial summary and payment collection for a ticket.
class BillEntity {
  final String id;
  final String tenantId;
  final String ticketId;
  final String billNumber;
  final int subtotal;
  final int taxAmount;
  final int discountAmount;
  final int total;
  final BillStatus status;
  final List<PaymentEntity> payments;

  const BillEntity({
    required this.id,
    required this.tenantId,
    required this.ticketId,
    required this.billNumber,
    required this.subtotal,
    required this.taxAmount,
    this.discountAmount = 0,
    required this.total,
    this.status = BillStatus.open,
    this.payments = const [],
  });

  int get totalPaid =>
      payments.fold<int>(0, (sum, p) => sum + p.amount);

  int get remainingBalance => total - totalPaid;

  bool get isFullyPaid => remainingBalance <= 0;

  factory BillEntity.fromJson(Map<String, dynamic> json) => BillEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        ticketId: json['ticket_id'] as String,
        billNumber: json['bill_number'] as String,
        subtotal: (json['subtotal'] as num).toInt(),
        taxAmount: (json['tax_amount'] as num).toInt(),
        discountAmount: (json['discount_amount'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num).toInt(),
        status: BillStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => BillStatus.open,
        ),
        payments: (json['payments'] as List<dynamic>? ?? [])
            .map((p) => PaymentEntity.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'ticket_id': ticketId,
        'bill_number': billNumber,
        'subtotal': subtotal,
        'tax_amount': taxAmount,
        'discount_amount': discountAmount,
        'total': total,
        'status': status.name,
        'payments': payments.map((p) => p.toJson()).toList(),
      };

  BillEntity copyWith({
    String? id,
    String? tenantId,
    String? ticketId,
    String? billNumber,
    int? subtotal,
    int? taxAmount,
    int? discountAmount,
    int? total,
    BillStatus? status,
    List<PaymentEntity>? payments,
  }) {
    return BillEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      ticketId: ticketId ?? this.ticketId,
      billNumber: billNumber ?? this.billNumber,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      total: total ?? this.total,
      status: status ?? this.status,
      payments: payments ?? this.payments,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BillEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          ticketId == other.ticketId &&
          billNumber == other.billNumber &&
          total == other.total &&
          status == other.status;

  @override
  int get hashCode =>
      Object.hash(id, tenantId, ticketId, billNumber, total, status);

  @override
  String toString() =>
      'BillEntity(id: $id, bill: $billNumber, total: $total, status: ${status.name})';
}
