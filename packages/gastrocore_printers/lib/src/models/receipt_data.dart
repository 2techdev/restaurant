/// Print-ready DTO for a customer receipt (fiş).
///
/// Constructed by the POS payment flow from [TicketEntity] + [PaymentEntity].
/// Templates consume this, never the raw domain entities — that keeps the
/// printers package Flutter-only without pulling business rules.
library;

import 'package:gastrocore_models/gastrocore_models.dart';

/// A payment line on the receipt footer.
class ReceiptPayment {
  final String method; // "cash", "card", "twint", "voucher"
  final int amountCents;
  final int changeCents;

  const ReceiptPayment({
    required this.method,
    required this.amountCents,
    this.changeCents = 0,
  });
}

/// A single MWST band (e.g. 8.1% dine-in food) summary row.
class ReceiptTaxLine {
  final String label; // "MWST 8.1%"
  final double ratePercent;
  final int netCents;
  final int taxCents;
  final int grossCents;

  const ReceiptTaxLine({
    required this.label,
    required this.ratePercent,
    required this.netCents,
    required this.taxCents,
    required this.grossCents,
  });
}

class ReceiptLineItem {
  final String name;
  final double quantity;
  final int unitPriceCents;
  final int lineTotalCents;
  final List<String> modifierLines; // "+ Extra cheese (+1.00)"
  final String? note;

  const ReceiptLineItem({
    required this.name,
    required this.quantity,
    required this.unitPriceCents,
    required this.lineTotalCents,
    this.modifierLines = const [],
    this.note,
  });

  factory ReceiptLineItem.fromOrderItem(OrderItemEntity item) => ReceiptLineItem(
        name: item.productName,
        quantity: item.quantity,
        unitPriceCents: item.unitPrice,
        lineTotalCents: item.subtotal,
        modifierLines: item.modifiers
            .map((m) => m.priceDelta == 0
                ? '+ ${m.modifierName}'
                : '+ ${m.modifierName} (${_money(m.priceDelta)})')
            .toList(),
        note: item.notes,
      );
}

class ReceiptData {
  // Header
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String? vatNumber; // CHE-xxx.xxx.xxx MWST
  final List<int>? logoPng;

  // Ticket meta
  final String ticketNumber;
  final String? tableLabel; // "Tisch 12" / "Takeaway"
  final String? waiterName;
  final String? cashierName;
  final int guestCount;
  final DateTime issuedAt;

  // Body
  final List<ReceiptLineItem> items;

  // Totals
  final int subtotalCents;
  final int discountCents;
  final int serviceChargeCents;
  final int grandTotalCents;

  // Tax breakdown (Swiss: one row per rate actually used on the ticket)
  final List<ReceiptTaxLine> taxLines;

  // Payment
  final List<ReceiptPayment> payments;

  // Footer
  final String? thankYouMessage;

  /// Optional payload to render as a QR code at the bottom — e.g. the
  /// fiscal invoice URL or a loyalty-program deep link.
  final String? qrPayload;

  const ReceiptData({
    required this.storeName,
    required this.storeAddress,
    required this.storePhone,
    this.vatNumber,
    this.logoPng,
    required this.ticketNumber,
    this.tableLabel,
    this.waiterName,
    this.cashierName,
    this.guestCount = 1,
    required this.issuedAt,
    required this.items,
    required this.subtotalCents,
    this.discountCents = 0,
    this.serviceChargeCents = 0,
    required this.grandTotalCents,
    this.taxLines = const [],
    this.payments = const [],
    this.thankYouMessage,
    this.qrPayload,
  });
}

String _money(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  return '$sign${(abs ~/ 100).toString()}.${(abs % 100).toString().padLeft(2, '0')}';
}
