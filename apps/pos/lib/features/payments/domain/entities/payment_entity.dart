/// Payment and bill entities for the payments domain.
///
/// A [BillEntity] represents the financial summary of a ticket.
/// One or more [PaymentEntity] records settle the bill (split payments
/// are supported). All monetary values are in cents.
library;

// ---------------------------------------------------------------------------
// PaymentMethod enum
// ---------------------------------------------------------------------------

/// Accepted payment methods.
enum PaymentMethod {
  cash,
  creditCard,
  debitCard,
  other,
}

// ---------------------------------------------------------------------------
// BillStatus enum
// ---------------------------------------------------------------------------

/// Lifecycle status of a bill.
enum BillStatus {
  /// Bill issued, awaiting payment.
  open,

  /// Some payments received but balance remains.
  partiallyPaid,

  /// Bill fully settled.
  fullyPaid,

  /// Bill voided (requires manager approval).
  voidStatus,
}

// ---------------------------------------------------------------------------
// PaymentEntity
// ---------------------------------------------------------------------------

/// A single payment transaction against a [BillEntity].
class PaymentEntity {
  final String id;
  final String tenantId;
  final String billId;
  final String ticketId;
  final PaymentMethod paymentMethod;

  /// Amount applied to the bill in cents.
  final int amount;

  /// Tip amount in cents.
  final int tipAmount;

  /// Amount tendered by the customer in cents (relevant for cash).
  final int tenderedAmount;

  /// Change returned to the customer in cents.
  final int changeAmount;

  /// External reference (e.g. card transaction ID, terminal receipt number).
  final String? reference;

  /// User ID of the staff member who processed this payment.
  final String receivedBy;

  /// When the payment was processed.
  final DateTime paidAt;

  // -------------------------------------------------------------------------
  // Expanded payment fields (OrderPin-compatible)
  // -------------------------------------------------------------------------

  /// Payment sub-channel (e.g. 'GHL:ECR', 'SumUp:BT').
  final String? paySubChannel;

  /// Physical form of payment ('scan', 'chip', 'swipe', 'contactless').
  final String? paymentForm;

  /// Card reference, QR code, or barcode identifier.
  final String? paymentReference;

  /// External payment channel ('ALIPAY', 'TWINT', 'WECHAT_PAY', etc.).
  final String? externalChannel;

  /// Payment ID from external / third-party system.
  final String? externalPaymentId;

  /// Name of the cashier who processed this payment.
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

  /// Create a copy with selectively overridden fields.
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
          amount == other.amount &&
          tipAmount == other.tipAmount &&
          tenderedAmount == other.tenderedAmount &&
          changeAmount == other.changeAmount &&
          reference == other.reference &&
          receivedBy == other.receivedBy &&
          paidAt == other.paidAt &&
          paySubChannel == other.paySubChannel &&
          paymentForm == other.paymentForm &&
          paymentReference == other.paymentReference &&
          externalChannel == other.externalChannel &&
          externalPaymentId == other.externalPaymentId &&
          cashierName == other.cashierName;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        billId,
        ticketId,
        paymentMethod,
        amount,
        tipAmount,
        tenderedAmount,
        changeAmount,
        reference,
        receivedBy,
        paidAt,
        paySubChannel,
        paymentForm,
        externalChannel,
        cashierName,
      );

  @override
  String toString() =>
      'PaymentEntity(id: $id, method: ${paymentMethod.name}, amount: $amount)';
}

// ---------------------------------------------------------------------------
// BillEntity
// ---------------------------------------------------------------------------

/// Financial summary and payment collection for a ticket.
class BillEntity {
  final String id;
  final String tenantId;
  final String ticketId;

  /// Human-readable bill number.
  final String billNumber;

  /// Subtotal before tax and discounts in cents.
  final int subtotal;

  /// Total tax amount in cents.
  final int taxAmount;

  /// Total discount amount in cents.
  final int discountAmount;

  /// Grand total in cents.
  final int total;

  final BillStatus status;

  /// Payments applied to this bill.
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

  /// Sum of all payment amounts in cents.
  int get totalPaid =>
      payments.fold<int>(0, (sum, p) => sum + p.amount);

  /// Remaining balance in cents.
  int get remainingBalance => total - totalPaid;

  /// Whether the bill has been fully settled.
  bool get isFullyPaid => remainingBalance <= 0;

  /// Create a copy with selectively overridden fields.
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
          subtotal == other.subtotal &&
          taxAmount == other.taxAmount &&
          discountAmount == other.discountAmount &&
          total == other.total &&
          status == other.status;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        ticketId,
        billNumber,
        subtotal,
        taxAmount,
        discountAmount,
        total,
        status,
      );

  @override
  String toString() =>
      'BillEntity(id: $id, bill: $billNumber, total: $total, status: ${status.name})';
}
