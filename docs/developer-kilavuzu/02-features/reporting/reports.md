# Reports (Raporlama)

Satış, ürün ve vardiya raporları. POS çoğunlukla özet raporu üretir, detaylı analiz `dashboard` app'inde yapılır.

**Dizinler**:
- `apps/pos/lib/features/reports/` - POS içi raporlama
- `apps/pos/lib/features/shifts/` - Vardiya kapanış raporu (Z-Bericht)
- `apps/pos/lib/features/audit_log/` - Denetim günlüğü

## POS Tarafında Var Olanlar

### Storno Log Ekranı
`apps/pos/lib/features/reports/presentation/screens/storno_log_screen.dart`

Void/iptal edilmiş item'ların listesi. Swiss kayıt zorunluluğu için önemli.

- Hangi kasiyer void etti
- Hangi zaman
- Hangi item, hangi tutar
- Sebep

Provider: `storno_log_provider.dart`.

### MWST CSV Export
`apps/pos/lib/features/reports/services/mwst_csv_export_service.dart`

İsviçre KDV beyannamesi için CSV export. Genelde muhasebe (Treuhänder) haftalik/aylik indirir.

Columns:
- Date
- Ticket ID
- Total net
- Total gross
- Tax amount (by rate)
- Payment method

`excel: ^4.0.6` paketi üzerinden export edilebilir (xlsx formatı). CSV tercih edilirse basit string writer.

## Vardiya Raporu (Z-Bericht)

`apps/pos/lib/features/shifts/`

Günlük kasa kapanışı. Swiss merchant için önemli; tüm kasaların kapatılması, farkın yazılması yasal.

### Shift Entity
```dart
class ShiftEntity {
  final String id;
  final String userId;           // hangi cashier
  final DateTime openedAt;
  final DateTime? closedAt;
  final int openingCashCents;    // başlangıç kasası
  final int? closingCashCents;   // kapanış sayımı
  final int totalSalesCents;     // hesaplanan total
  final int? cashDifferenceCents; // kapanış - beklenen
}
```

### Akış
1. Vardiya açılışında -> "Kasada ne kadar para var?" -> `openingCashCents`.
2. Gün boyunca satışlar `totalSalesCents`'e eklenir.
3. Vardiya kapanışında -> "Kasada şu an ne kadar?" -> `closingCashCents`.
4. Beklenen: `openingCashCents + cashSalesCents - payoutsCents`.
5. Fark: `closing - expected`. Pozitif = fazla, negatif = eksik.
6. `ShiftReport` yazdırılır (yazıcı varsa), PDF olarak da kaydedilir.

Kaynak: `apps/pos/lib/features/shifts/data/` + `presentation/`.

## Dashboard App (Daha Zengin Rapor)

`apps/dashboard/` ayrı bir Flutter app. Genelde yöneticinin web/masaüstü üzerinde açtığı analytics paneli.

İçerdiği raporlar (backend üzerinden):
- `/api/v1/reports/sales` - Günlük/haftalık/aylık satış
- `/api/v1/reports/products` - Ürün performansı (top seller, düşük stok)
- `/api/v1/reports/shifts` - Vardiya özetleri
- `/api/v1/reports/employees` - Cashier performansı
- `/api/v1/reports/vat` - KDV özeti (Swiss için quarterly filing)

POS'ta bu ekranlar yok, sadece POS'ta kendi satış özeti var.

## Audit Log

`apps/pos/lib/features/audit_log/`

Denetim için önemli:
```dart
class AuditLogEntry {
  final String id;
  final String userId;           // kim yaptı
  final String action;           // payment_created, void_item, shift_close vb
  final Map<String, dynamic> details;  // JSON
  final DateTime timestamp;      // UTC
  final String? deviceId;
}
```

DAO: `features/audit_log/data/daos/audit_log_dao.dart`.

Tetiklendiği yerler:
- Her ödeme (`payment_created`)
- Her void (`void_item`)
- Her override (`manager_override_used`)
- Vardiya açma/kapama (`shift_open`, `shift_close`)
- Product edit (`product_updated`)
- User login (`auth_success`, `auth_failed`)

İsviçre için: her işlem denetlenebilir olmalı, audit log'u sürekli sync cloud'a itilir (tamper-proof için).

## PDF + Excel Export

`pdf: ^3.10.8` - PDF üretimi (rapor, makbuz).
`printing: ^5.13.2` - Yazıcıya basma.
`excel: ^4.0.6` - XLSX üretimi.

Ortak pattern:
```dart
final pdf = pw.Document();
pdf.addPage(pw.Page(build: (ctx) => pw.Column([...])));
final bytes = await pdf.save();
await Printing.layoutPdf(onLayout: (_) async => bytes);
```

## Gelecek Raporlar (Henüz Yok)

Plan aşamasında:
- Günlük X-Bericht (vardiya devam ederkenki anlık özet).
- Ödeme method breakdown (cash vs kart vs TWINT).
- Modifier performance (hangi extra en çok satan).
- Top tables (masa bazlı ciro).

Bu raporlar dashboard tarafında çoğu mevcut, POS'a ihtiyaç duyulursa port edilecek.

## Test

- Boş vardiya kapat -> total 0, difference 0.
- Satış yap, void et -> audit_log 2 satır.
- Storno log ekranı -> void'leri listeler.
- CSV export -> file system'e xlsx düşer.
