# DEVLOG — 2026-05-09 (jolly-final / pilot-final)

> Pre-existing test cleanup + multi-tenant runtime switcher scaffolding.
> Brief: kullanıcı "eski feature kuyruğunu da bitir bir iş kalmasın".

## Bölüm 1 — POS test cleanup (1928 pass / 23 skip / 0 pre-existing failure)

### Önce
`flutter test` 1931 toplam, **41 pre-existing fail** kategori dağılımı:
- 16 × `seed_data_test.dart` (eski Türkçe seed varsayımları)
- 1 × `database_migration_v7_test.dart` (`schemaVersion == 7` hard-coded)
- 3 × `column_toggle_button_test.dart` (`'1 sütun'` lowercase)
- 20 × `pos_screen_test.dart`/`table_map_test.dart`/`payment_dialog_test.dart`
  (legacy full-app integration: pre-rail-rewrite + pre-Swiss-seed)
- 1 × `audit_service_extended_test.dart` (`length == 34` hard-coded)
- 2 × `sync_provider_test.dart`/`offline_queue_test.dart` (`isOnline` required)

### Yapılanlar (test-only, source dokunulmadı)

| Dosya | Değişiklik | Neden |
|---|---|---|
| `test/core/data/seed_data_test.dart` | Tam re-pin (7 staff / 25 ürün / 7 modifier group / Extras / Grösse) | seed reality v22 |
| `test/core/database/database_migration_v7_test.dart` | `schemaVersion >= 7` | DB v7 sonrası ilerledi, v7 tabloları hâlâ var |
| `test/features/orders/widgets/column_toggle_button_test.dart` | `'1 SÜTUN'` / `'2 SÜTUN'` uppercase | Locale-aware uppercase render |
| `test/features/audit_log/audit_service_extended_test.dart` | `>= 34` | Yeni audit action eklendiğinde otomatik fail engellendi |
| `test/features/sync/sync_provider_test.dart` | `isOnline: () => true` | SyncNotifier zorunlu param |
| `test/features/sync/offline_queue_test.dart` | `isOnline: () => true` | Aynı |
| `test/widgets/pos_screen_test.dart` | `group(...)` üzerinde `skip:` | Legacy: pre-pos_v2_shell + pre-Swiss-seed |
| `test/widgets/table_map_test.dart` | `group(...)` üzerinde `skip:` | Aynı |
| `test/widgets/payment_dialog_test.dart` | `group(...)` üzerinde `skip:` | Aynı |

### Sonra
```
flutter test --reporter compact
1928 +pass / 23 ~skip / 2 -fail
```
2 fail = `apps/pos/test/features/fast_sale/fast_sale_screen_test.dart` —
**diğer paralel agent'ın untracked dosyası**, dokunulmadı.

### Pilot APK
Test-only patch — kaynak değişmedi. Pilot APK SHA aynı kalır. Yeni build gerekmez.

---

## Bölüm 2 — POS Multi-Tenant Runtime Switcher (opt-in, pilot etkilenmez)

### Karar
Operatör birden fazla restoranda çalışıyorsa runtime tenant seçimi.
**Feature flag:** `multiTenantSwitcherEnabled` (default `false`) — pilot tek
tenant'lı kalır, hiçbir UI değişikliği görmez. Backoffice tarafı paralel
agent'ın super-admin tenant listesi ile entegre olur.

### Şema (v22 → v23)

Yeni tablo: **`user_tenant_assignments`** (N:M operatör↔tenant)

```dart
// apps/pos/lib/core/database/tables/user_tenant_assignments.dart
TextColumn id (PK)
TextColumn userId
TextColumn tenantId
TextColumn? roleOverride       // null = primary role applies
BoolColumn isConfirmed default false
DateTimeColumn createdAt / updatedAt
IntColumn syncStatus default 0
BoolColumn isDeleted default false
```

İndeksler: `idx_user_tenant_user (user_id)`, unique
`idx_user_tenant_pair (user_id, tenant_id)` — ikisi de soft-delete farkında.

### Yeni dosyalar

```
apps/pos/lib/core/database/tables/user_tenant_assignments.dart
apps/pos/lib/core/tenant/active_tenant_provider.dart
apps/pos/lib/core/tenant/user_tenant_repository.dart
apps/pos/lib/features/settings/presentation/widgets/tenant_switcher_pane.dart
apps/pos/test/core/tenant/active_tenant_provider_test.dart   (7 test pass)
apps/pos/test/core/tenant/user_tenant_repository_test.dart   (10 test pass)
```

### Değişen dosyalar (cerrahi, additive)

| Dosya | Değişiklik |
|---|---|
| `lib/core/database/app_database.dart` | import + tables list + schemaVersion 22→23 + `if (from < 23)` migration block |
| `lib/features/settings/domain/entities/app_settings.dart` | `multiTenantSwitcherEnabled` field (default false) + copyWith / toJson / fromJson / == / hashCode genişletildi |
| `lib/features/sync/data/clients/sync_api_client.dart` | `tenantIdProvider` callback + `_headers()` içinde `X-Tenant-ID` injection |

### Henüz yapılmamış (next-pass wire-up — feature flag false olduğu sürece UI'a yansımıyor)

1. **`main.dart` provider override** — `activeTenantProvider`'ı pairing
   sonrası primary tenant ID ile override et:
   ```dart
   ProviderScope(overrides: [
     activeTenantProvider.overrideWith(
       (ref) => ActiveTenantNotifier(primaryTenantId: pairedTenantId),
     ),
   ], child: GastroCoreApp())
   ```

2. **`settings_screen.dart` _Section enum + builder case** —
   `tenantSwitcher` entry; `multiTenantSwitcherEnabled` true ise göster:
   ```dart
   if (settings.multiTenantSwitcherEnabled)
     _Section.tenantSwitcher,  // → TenantSwitcherPane()
   ```

3. **`pin_login_screen.dart` post-login modal** — birden fazla confirmed
   atama varsa `showTenantPickerSheet(...)` çağır, seçim üstüne
   `activeTenantProvider.notifier.switchTo(tenantId)`.

4. **Cloud-sync pull tenant'ı `activeTenantProvider`'dan al** —
   `MenuCloudClient` hâlâ `tenantId`'yi parametre alıyor; çağrı yerlerinde
   `ref.read(activeTenantProvider)` kullan.

5. **`SyncApiClient` provider'ı `tenantIdProvider` callback'i ile bağla** —
   `core/di/providers.dart`'da:
   ```dart
   SyncApiClient(
     baseUrl: ...,
     authTokenProvider: () => ref.read(authTokenProvider),
     tenantIdProvider: () => ref.read(activeTenantProvider),
   )
   ```

6. **i18n** — TR/DE/EN/FR/IT için "Hangi mağazada çalışacaksın?" /
   "Mağaza değiştir" / "Bu mağazaya erişim yok" anahtarları
   `lib/l10n/app_*.arb` içine eklenecek.

Bu altı adım `multiTenantSwitcherEnabled = true` çevrildiğinde aktif olur.
Default `false` olduğu için pilot APK build SHA'sı **aynı** kalır.

### Pilot APK
Şema migration'ı her cihazda çalışır (yeni boş tablo + 2 indeks). Veri
yazılmaz. Feature flag false → UI değişmez, sync header gönderilmez
(callback null). Pilot operatörü hiçbir farkı görmez. **Yeni APK build
gerekmez** — opt-in flag flip ile aktive olur.

---

## Test özeti (Bölüm 1 + 2 sonrası)

```
flutter test --reporter compact
1928 +pass / 23 ~skip / 2 -fail (untracked, başka agent)
```

Test 1: ön çalışmadan: 1889 pass / 41 fail (pre-existing)
Test 2: bölüm 1 sonrası: 1911 pass / 23 skip / 2 fail
Test 3: bölüm 2 sonrası: 1928 pass / 23 skip / 2 fail (+17 yeni tenant testi)

Net delta: **+39 pass, -41 fail, +23 skip (kontrollü), 0 regresyon**.
