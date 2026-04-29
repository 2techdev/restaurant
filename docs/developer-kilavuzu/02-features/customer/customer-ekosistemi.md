# Customer Ekosistemi (Customers + Reservations + Tables)

Müşteri ile ilgili üç feature birbirine bağlı. Tek bir dokümanda topladık çünkü veri modelleri iç içe geçiyor.

**Dizinler**:
- `apps/pos/lib/features/customers/`
- `apps/pos/lib/features/reservations/`
- `apps/pos/lib/features/tables/`

## Customers

### Dosyalar
```
features/customers/
├── data/           # CustomerRepository impl
├── domain/
│   └── entities/
│       ├── customer_entity.dart
│       └── customer_address_entity.dart
└── presentation/
```

### `CustomerEntity`
```dart
class CustomerEntity {
  final String id;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final List<CustomerAddressEntity> addresses;
  final int loyaltyPoints;
  final DateTime? birthday;
  final String? notes;
  // ...
}
```

Adres ayrı entity'de (`CustomerAddressEntity`): street, zip, city, country. Teslimat siparişlerinde veya QR-Bill fatura adresi için kullanılır.

### DB Tablolari
- `Customers`
- `CustomerAddresses` (many-to-one)
- `LoyaltyTransactions` - puan kazanim/kullanim hareketleri

### Loyalty (Sadakat)

`LoyaltyTransactions`:
```dart
class LoyaltyTransactionEntity {
  final String customerId;
  final String ticketId;
  final int pointsDelta;          // +100 (kazan) veya -50 (kullan)
  final DateTime createdAt;
}
```

Kural: Her 10 CHF harcama -> +1 puan. 100 puan = 5 CHF indirim. Bu kural code'da parameterize değil, domain'de sabit. Çoklu merchant için config'lenmesi gerekebilir.

### Kim çağırır?
- `OrderPaymentScreen` - ödeme sırasında müşteri seçilirse puan uygulanır.
- `CustomersListScreen` - yönetim ekranı.
- `CustomerDetailScreen` - profil, sipariş geçmişi, puan bakiyesi.

## Reservations

### Dosyalar
```
features/reservations/
├── data/           # ReservationRepository impl
├── domain/
│   └── entities/
│       └── reservation_entity.dart
└── presentation/
```

### `ReservationEntity`
```dart
class ReservationEntity {
  final String id;
  final String? customerId;       // müşteri kayıtlıysa
  final String customerName;      // yoksa walk-in ismi
  final String? phone;
  final DateTime reservedAt;
  final int guestCount;
  final String? tableId;          // pre-assigned masa
  final ReservationStatus status; // booked, confirmed, seated, noShow, cancelled
  final String? notes;
}
```

### Status akışı
```
booked -> confirmed -> seated (masaya oturdu) -> ticket yaratıldı
       -> cancelled
       -> noShow (gelmedi)
```

### Kim çağırır?
- Yönetim panelindeki rezervasyon takvimi (genellikle `dashboard` app).
- POS'ta "gelen rezervasyonlar" paneli.
- Seated durumuna çekildiğinde otomatik bir ticket açılır (opsiyonel feature).

## Tables

### Dosyalar
```
features/tables/
├── data/           # TableRepository impl
├── domain/
│   └── entities/
│       ├── floor_entity.dart
│       ├── restaurant_table_entity.dart
│       └── table_layout_entity.dart (var ise)
└── presentation/
```

### Entity'ler
```dart
class FloorEntity {
  final String id;
  final String name;              // "Zeminkat", "Teras", "Bar"
  final int sortOrder;
}

class RestaurantTableEntity {
  final String id;
  final String floorId;
  final String label;             // "Tisch 5", "T-12"
  final int capacity;             // kaç kişilik
  final double x;                 // layout pozisyonu (px veya %)
  final double y;
  final TableShape shape;         // square, circle, rectangle
  final TableStatus status;       // free, occupied, reserved, closed
}
```

### Masa Durumu (Status)
- `free` - boş, satışa açık
- `occupied` - müşteri oturdu (aktif ticket var)
- `reserved` - rezervasyon için tutuluyor (henüz gelmedi)
- `closed` - kullanımda değil (tatil vs)

### Kim çağırır?
- POS shell'i bir masa seçildiğinde o masaya ticket açar.
- Waiter flavor'da masa planı ana ekran.
- Dashboard app'te masa düzeni editörü.

## Üç Feature'ın Kesişimi

1. **Rezervasyon + Masa**: Rezervasyon `tableId` alanı ile bir masaya peg'li.
2. **Ticket + Masa**: `tickets.table_id` foreign key.
3. **Ticket + Customer**: `tickets.customer_id` foreign key (opsiyonel).
4. **Rezervasyon + Customer**: `reservations.customer_id` foreign key (opsiyonel).

Böylece:
- Bir müşterinin geçmişi: customer -> tickets -> sipariş detayları.
- Bir masanın gün boyunca kim tarafından kullanıldığı: table -> tickets.
- Rezervasyon tamamlandığında ticket zaten doğru müşteri + masaya bağlanmış olur.

## Swiss KVKK / GDPR Konusu

İsviçre FADP ve AB GDPR sebebiyle müşteri verisi:
- Opt-in: müşteri açık rıza vermeden email / phone kaydetme.
- Silme hakkı: `CustomerRepository.delete` - ticket history'de `customer_id`'yi `null`'a çekiyor, hard delete değil (audit trail korunur).
- Loyalty puanları silinmez, anonimize edilir.

Backend bu kuralı enforce eder (API endpoint level). POS yerel olarak da aynı davranışı takip eder.

## Online Orders Bağlantısı

`features/online_orders/` - cloud'dan gelen online siparişler POS'ta ayrı bir sekmede görünür. Müşteri kaydı zaten online'da olduğu için `customer_id` hazır gelir. POS otomatik olarak local `customers` tablosuna upsert eder.

## Test

- Rezervasyon oluştur -> masa `reserved` olur.
- Müşteri geldi -> status `seated`, ticket otomatik.
- Ticket kapandı -> masa tekrar `free`.
- Müşteri silindi -> ticket'ta `customer_id = null`, diğer veriler kalır.
