/// Baskı modülleri için paylaşımlı veri modelleri.
///
/// - [MwStCode]          — İsviçre MwSt (KDV) oranları (A=%8.1, B=%2.6, C=%3.8)
/// - [SwissReceiptData]  — Satış fişi (Verkaufsbeleg) verisi
/// - [KitchenTicketData] — Mutfak adisyonu (Bestellbon) verisi
/// - [ShiftReportData]   — Z/X Raporu verisi
library;

// ============================================================================
// YARDIMCI FONKSİYONLAR
// ============================================================================

/// Cent cinsinden CHF tutarını formatlar. Örnek: 3375 → 'CHF 33.75'
String formatChf(int cents) {
  final isNeg = cents < 0;
  final abs = cents.abs();
  return '${isNeg ? '-' : ''}CHF ${(abs / 100).toStringAsFixed(2)}';
}

/// Sadece sayısal kısım (CHF prefix olmadan). Örnek: 3375 → '33.75'
String formatChfAmt(int cents) {
  final isNeg = cents < 0;
  final abs = cents.abs();
  return '${isNeg ? '-' : ''}${(abs / 100).toStringAsFixed(2)}';
}

// ============================================================================
// İSVİÇRE MWST KODU
// ============================================================================

/// İsviçre MwSt (KDV) oranı.
///
/// - A = %8.1 — Normalsatz (restoran, bar)
/// - B = %2.6 — Reduzierter Satz (paket gıda)
/// - C = %3.8 — Sondersatz (konaklama)
enum MwStCode {
  a,
  b,
  c;

  /// Büyük harf kod harfi: 'A', 'B', 'C'
  String get code => name.toUpperCase();

  double get rate {
    switch (this) {
      case MwStCode.a:
        return 8.1;
      case MwStCode.b:
        return 2.6;
      case MwStCode.c:
        return 3.8;
    }
  }

  String get label {
    switch (this) {
      case MwStCode.a:
        return 'Normalsatz';
      case MwStCode.b:
        return 'Reduzierter Satz';
      case MwStCode.c:
        return 'Sondersatz';
    }
  }

  /// Kod harfinden [MwStCode] döndür. Bilinmeyen kod → [MwStCode.a].
  static MwStCode fromCode(String code) {
    switch (code.toUpperCase()) {
      case 'A':
        return MwStCode.a;
      case 'B':
        return MwStCode.b;
      case 'C':
        return MwStCode.c;
      default:
        return MwStCode.a;
    }
  }

  /// Efektif vergi oranından MwSt kodunu tahmin et.
  /// 0 ve ≤3.2% → B, ≤5.0% → C, diğer → A
  static MwStCode fromRate(double rate) {
    if (rate <= 0.0) return MwStCode.b;
    if (rate <= 3.2) return MwStCode.b;
    if (rate <= 5.0) return MwStCode.c;
    return MwStCode.a;
  }

  /// Ürün [taxGroup] ve servis tipine göre doğru MwSt kodunu döndür.
  ///
  /// İsviçre kuralları:
  /// - accommodation          → C (3.8%)
  /// - food (takeaway)        → B (2.6%)
  /// - food (dine-in)         → A (8.1%)
  /// - beverage, alcohol, vb. → A (8.1%, always)
  static MwStCode forProduct({
    required String taxGroup,
    required bool isDineIn,
  }) {
    if (taxGroup == 'accommodation') return MwStCode.c;
    if (!isDineIn && taxGroup == 'food') return MwStCode.b;
    return MwStCode.a;
  }
}

// ============================================================================
// SATIŞ FİŞİ — VERİ MODELLERİ
// ============================================================================

/// Satış fişi kalemi.
class SwissReceiptItem {
  const SwissReceiptItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.mwstCode,
    this.unit = 'Stk',
    this.modifiers = const [],
    this.discountAmount = 0,
    this.notes,
  });

  final String name;
  final double quantity;

  /// Birimi: 'Stk', 'kg', 'Port.', vb.
  final String unit;

  /// Birim fiyat (cents / Rappen).
  final int unitPrice;

  /// Satır toplamı (cents, kalem indirimi uygulanmış).
  final int totalPrice;

  /// Kalem indirimi (cents).
  final int discountAmount;

  final MwStCode mwstCode;
  final List<String> modifiers;
  final String? notes;
}

/// Ödeme satırı.
class SwissPaymentLine {
  const SwissPaymentLine({required this.method, required this.amount});

  /// Gösterim etiketi: 'Bar', 'Karte', 'TWINT', vb.
  final String method;

  /// Tutar (cents).
  final int amount;
}

/// Restoran bilgileri (fiş başlığı).
class RestaurantInfo {
  const RestaurantInfo({
    required this.name,
    this.address,
    this.phone,
    this.mwstNr,
    this.footerText,
    this.qrData,
  });

  final String name;
  final String? address;
  final String? phone;

  /// İsviçre MWST numarası: 'CHE-123.456.789 MWST'
  final String? mwstNr;

  final String? footerText;
  final String? qrData;
}

/// İsviçre satış fişi (Verkaufsbeleg) veri modeli.
class SwissReceiptData {
  const SwissReceiptData({
    required this.restaurantName,
    required this.receiptNo,
    required this.items,
    required this.total,
    this.address,
    this.phone,
    this.mwstNr,
    this.dateTime,
    this.cashierName,
    this.tableName,
    this.orderNo,
    this.orderTypeLabel,
    this.subtotal,
    this.discountAmount = 0,
    this.roundingAmount = 0,
    this.mwstBreakdown = const {},
    this.payments = const [],
    this.tenderedAmount = 0,
    this.changeAmount = 0,
    this.footerText,
    this.qrData,
    this.printWidth = 42,
    this.openDrawer = false,
  });

  // ---- Başlık ----
  final String restaurantName;
  final String? address;
  final String? phone;

  /// CHE-123.456.789 MWST
  final String? mwstNr;

  // ---- Meta ----
  final String receiptNo;
  final DateTime? dateTime;
  final String? cashierName;
  final String? tableName;
  final String? orderNo;

  /// Servis türü etiketi: 'Hier essen' veya 'Zum Mitnehmen'.
  /// Fişin meta bölümünde gösterilir (MWST oranı seçimi açısından önemli).
  final String? orderTypeLabel;

  // ---- Kalemler ----
  final List<SwissReceiptItem> items;

  // ---- Tutarlar (cents) ----
  final int total;
  final int? subtotal;
  final int discountAmount;

  /// 5-Rappen yuvarlama tutarı (cents).
  ///
  /// Pozitif = yukarı yuvarlama (+3 Rappen), negatif = aşağı (-2 Rappen).
  /// Nakit ödemelerde sıfırdan farklıysa fiş üzerinde gösterilir.
  /// Kart / TWINT ödemelerinde her zaman 0 olmalıdır.
  final int roundingAmount;

  /// MwSt kodu → brüt tutar (cents). Vergi hesabı builder'da yapılır.
  /// Örnek: {'A': 288850, 'B': 9750}
  final Map<String, int> mwstBreakdown;

  // ---- Ödeme ----
  final List<SwissPaymentLine> payments;

  /// Verilen nakit (cents).
  final int tenderedAmount;

  /// Üstü kalan (cents).
  final int changeAmount;

  // ---- Footer ----
  final String? footerText;
  final String? qrData;

  // ---- Seçenekler ----
  /// Kağıt genişliği (karakter): 80mm → 42, 58mm → 32.
  final int printWidth;

  /// Fişten sonra kasa çekmecesini aç.
  final bool openDrawer;
}

// ============================================================================
// ADİSYON — VERİ MODELLERİ
// ============================================================================

/// Mutfak adisyonu kalemi.
class KitchenItem {
  const KitchenItem({
    required this.name,
    required this.quantity,
    this.modifiers = const [],
    this.notes,
    this.isVoid = false,
  });

  final String name;
  final double quantity;
  final List<String> modifiers;
  final String? notes;

  /// İptal edilmiş kalem — STORNO olarak yazdırılır.
  final bool isVoid;
}

/// Mutfak adisyonu (Bestellbon / Kitchen Order Ticket) veri modeli.
class KitchenTicketData {
  const KitchenTicketData({
    required this.tableNo,
    required this.orderNo,
    required this.items,
    required this.dateTime,
    this.waiterName,
    this.courseLabel,
    this.printerGroup,
    this.notes,
    this.printWidth = 42,
  });

  final String tableNo;
  final String orderNo;
  final String? waiterName;

  /// Kurs etiketi: 'Gang 1 - Vorspeise', 'Gang 2 - Hauptgang', vb.
  final String? courseLabel;

  /// Yazıcı grubu: 'Kueche', 'Bar', 'Cold Kitchen', vb.
  final String? printerGroup;

  final DateTime dateTime;
  final List<KitchenItem> items;
  final String? notes;
  final int printWidth;
}

// ============================================================================
// ADİSYON — CHECK/BILL DATA MODELS
// ============================================================================

/// Adisyon (check/bill) line item — no payment info.
class AdisyonItem {
  const AdisyonItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.unit = 'Stk',
    this.modifiers = const [],
    this.discountAmount = 0,
  });

  final String name;
  final double quantity;
  final String unit;

  /// Unit price in cents.
  final int unitPrice;

  /// Line total in cents (after item discount).
  final int totalPrice;

  /// Item-level discount in cents.
  final int discountAmount;

  final List<String> modifiers;
}

/// Check/bill (Adisyon) data model.
///
/// Used to print an interim bill for the customer without closing the order.
/// No payment section — customer sees items + total only.
class AdisyonData {
  const AdisyonData({
    required this.restaurantName,
    required this.items,
    required this.total,
    this.address,
    this.tableName,
    this.orderNo,
    this.cashierName,
    this.subtotal,
    this.discountAmount = 0,
    this.mwstBreakdown = const {},
    this.dateTime,
    this.footerText,
    this.printWidth = 42,
  });

  final String restaurantName;
  final String? address;
  final String? tableName;
  final String? orderNo;
  final String? cashierName;
  final List<AdisyonItem> items;

  /// Grand total in cents.
  final int total;

  /// Subtotal before order-level discount, in cents.
  final int? subtotal;

  /// Order-level discount in cents.
  final int discountAmount;

  /// MwSt code → gross amount in cents. Same format as [SwissReceiptData.mwstBreakdown].
  final Map<String, int> mwstBreakdown;

  final DateTime? dateTime;

  /// Override footer text (default: 'Bitte zahlen / L\'addition s\'il vous plaît').
  final String? footerText;

  /// Paper width in characters: 80mm → 42, 58mm → 32.
  final int printWidth;
}

// ============================================================================
// Z / X RAPORU — VERİ MODELLERİ
// ============================================================================

/// MwSt raporu kalemi (tek oran için).
class MwStReportEntry {
  const MwStReportEntry({
    required this.code,
    required this.grossAmount,
  });

  final MwStCode code;

  /// Brüt tutar (cents, vergi dahil).
  final int grossAmount;

  /// Vergi tutarı: gross × rate / (100 + rate)
  int get taxAmount =>
      (grossAmount * code.rate / (100 + code.rate)).round();

  /// Net tutar (vergisiz): gross - tax
  int get netAmount => grossAmount - taxAmount;
}

/// Gün sonu (Z) veya ara (X) raporu veri modeli.
class ShiftReportData {
  const ShiftReportData({
    required this.reportTitle,
    required this.reportNo,
    required this.shiftStart,
    required this.printedAt,
    this.cashierName,
    this.terminalNo,
    this.shiftEnd,
    this.grossSales = 0,
    this.totalDiscount = 0,
    this.netSales = 0,
    this.totalReturns = 0,
    this.netRevenue = 0,
    this.paymentBreakdown = const {},
    this.mwstEntries = const [],
    this.orderCount = 0,
    this.voidCount = 0,
    this.returnCount = 0,
    this.openingFloat,
    this.closingFloat,
    this.printWidth = 42,
  });

  /// 'Z-RAPPORT' veya 'X-RAPPORT'
  final String reportTitle;

  /// Sıralı rapor numarası.
  final int reportNo;

  final String? cashierName;
  final String? terminalNo;

  final DateTime shiftStart;

  /// Z raporu kapanış zamanı. X raporu için null olabilir.
  final DateTime? shiftEnd;

  final DateTime printedAt;

  // ---- Satış toplamları (cents) ----
  final int grossSales;
  final int totalDiscount;
  final int netSales;
  final int totalReturns;
  final int netRevenue;

  /// Ödeme yöntemi → tutar (cents). Örnek: {'Bar': 125000, 'TWINT': 32500}
  final Map<String, int> paymentBreakdown;

  /// Her MwSt oranı için rapor kalemi.
  final List<MwStReportEntry> mwstEntries;

  // ---- İstatistikler ----
  final int orderCount;
  final int voidCount;
  final int returnCount;

  // ---- Kasa (cents, null ise bölüm yazdırılmaz) ----
  /// Kasa açılış tutarı.
  final int? openingFloat;

  /// Kasa kapanış sayımı.
  final int? closingFloat;

  /// Beklenen - sayılan fark.
  int? get cashDifference {
    if (openingFloat == null || closingFloat == null) return null;
    final cashIn = paymentBreakdown.entries
        .where((e) => e.key.toLowerCase() == 'bar')
        .fold<int>(0, (sum, e) => sum + e.value);
    return closingFloat! - (openingFloat! + cashIn);
  }

  final int printWidth;
}
