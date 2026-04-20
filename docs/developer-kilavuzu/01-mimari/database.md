# Database (Drift)

POS cihazda SQLite kullanır, üstüne `drift ^2.22.1` ORM. Tüm tablo tanımları tek bir `AppDatabase` sınıfında birleşir.

## Giriş Noktası

**Dosya**: `apps/pos/lib/core/database/app_database.dart`

```dart
@DriftDatabase(
  tables: [
    Tenants, Users, Categories, Products, ModifierGroups, Modifiers,
    ProductModifierGroups, Floors, RestaurantTables, Tickets, OrderItems,
    OrderItemModifiers, Bills, Payments, Shifts, CashMovements,
    KitchenTickets, KitchenTicketItems, Receipts, SyncQueue, SyncMetadata,
    AuditLog, TaxProfiles, ...
  ],
)
class AppDatabase extends _$AppDatabase {
  @override
  int get schemaVersion => 12;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async { ... },
    onCreate: (m) async { ... },
  );
}
```

Generated partial: `app_database.g.dart` (build_runner ürünü, commit'e girer).

## Schema Versiyonu

**Mevcut**: `schemaVersion = 12` (`app_database.dart:106`)

Her tablo değişikliği (yeni kolon, yeni tablo, rename, drop) şunları gerektirir:
1. `schemaVersion` bir artar.
2. `onUpgrade` callback'ine yeni migration case eklenir.
3. `dart run build_runner build --delete-conflicting-outputs` ile `app_database.g.dart` yenilenir.
4. Commit: hem `.dart` hem `.g.dart` birlikte.

## Tablo Dosyaları

**Dizin**: `apps/pos/lib/core/database/tables/`

Örnek: `products.dart`:
```dart
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get priceCents => integer()();
  TextColumn get categoryId => text().references(Categories, #id)();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

Temel tablolar ve sorumlulukları:

| Tablo | Ne tutar |
|---|---|
| `Tenants` | Çoklu merchant izolasyon (bir POS birden fazla tenant'a hizmet verebilir) |
| `Users` | Cashier/manager kayıtları + hashed PIN |
| `Categories` | Menü kategorileri (Getränke, Vorspeisen...) |
| `Products` | Ürünler, fiyat, kategori, resim |
| `Modifiers` + `ModifierGroups` | Extra peynir, acılı, az buzlu vb |
| `Tickets` | Aktif ve kapalı sepet kayıtları |
| `OrderItems` | Ticket kalemleri |
| `OrderItemModifiers` | Ticket kaleminin modifier'ları |
| `Bills` | Ödeme öncesi kapatılmış faturalar |
| `Payments` | Nakit / kart / TWINT ödeme kayıtları |
| `KitchenTickets` + `KitchenTicketItems` | Mutfağa giden sipariş |
| `Receipts` | Basılan makbuzlar |
| `SyncQueue` | Outbox - cloud'a gönderilmemiş yazmalar |
| `SyncMetadata` | Son pull tarihi, device ID, tenant ID |
| `AuditLog` | Kim, ne zaman, ne yaptı (override, void, refund) |
| `TaxProfiles` | KDV oranları (country_config.dart'a yedek) |
| `FiscalSignatures` | Almanya için TSE imzalari |
| `Shifts` | Vardiya açma/kapama + kasa farkı |
| `CashMovements` | Bozukluk girişi/çıkışı |
| `Customers` + `CustomerAddresses` | Müşteri kayıtları |
| `Reservations` | Rezervasyonlar |
| `LoyaltyTransactions` | Puan kazanımları/kullanımları |
| `ManagerPins` | Override için yönetici PIN'leri |
| `LicenseTokens` | Ed25519 signed lisans |
| `LanSyncPeers` | LAN içinde keşfedilen cihazlar |

## DAO'lar

Bazı tablolar için ayrı DAO (Data Access Object). Drift'in native pattern'i.

Örnek: `features/audit_log/data/daos/audit_log_dao.dart`

```dart
@DriftAccessor(tables: [AuditLog])
class AuditLogDao extends DatabaseAccessor<AppDatabase> with _$AuditLogDaoMixin {
  AuditLogDao(super.db);
  Future<void> insert(...) { ... }
  Stream<List<AuditLogData>> watchRecent(int limit) { ... }
}
```

DAO'lar feature içinde yaşar (`features/<f>/data/daos/`), `AppDatabase` onları tanır çünkü tablo zaten `@DriftDatabase` listesinde.

## Sync Queue (Outbox)

`SyncQueue` tablosu offline-first'ün kalbidir:
- Her lokal yazma (ticket yaratma, ödeme alma, vardiya kapatma) aynı transaction'da `SyncQueue`'a bir satır atar.
- Bir arka plan timer bu satırları `/api/v1/sync/push`'a batch yükler.
- Başarılı olan satırlar silinir.

Detay: `packages/gastrocore_sync/` + `apps/pos/lib/features/sync/`.

## Veri Tabanı Konumu

`AppDatabase._openConnection`:
```dart
final dbFolder = await getApplicationDocumentsDirectory();
final file = File(p.join(dbFolder.path, 'gastrocore_pos.sqlite'));
```

- Android: `/data/data/ch.twotech.gastrocore.pos/app_flutter/gastrocore_pos.sqlite`
- Web: IndexedDB'ye redirect edilir (wasm sqlite kullanılır).

## Geliştirme İpucu

Schema değişikliği sırasında APK geriye uyumsuz olabilir. Test cihazında:
```bash
adb shell pm clear ch.twotech.gastrocore.pos
```
Veya `AppDatabase.migration.onUpgrade` case'i eklemeden önce emülatörde sıfırdan kur.

**Drift query'leri type-safe'dir.** `build_runner` çalıştığında `Products` tablosundan `ProductsData` class'ı, `ProductsCompanion` insert helper'ı üretir. `SELECT` / `INSERT` DSL Dart'ın içinde:

```dart
final rows = await (select(products)..where((p) => p.categoryId.equals(catId))).get();
```

## Test

`test/core/database/` altında `AppDatabase` için unit test'ler var. `NativeDatabase.memory()` ile in-memory SQLite kullanılır:

```dart
final db = AppDatabase.memory();
await db.into(db.products).insert(ProductsCompanion.insert(...));
```

Bkz [04-dev-workflow/test-calistir.md](../04-dev-workflow/test-calistir.md).
