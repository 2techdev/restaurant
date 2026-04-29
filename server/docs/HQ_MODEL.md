# HQ (Headquarters) Chain Restaurant Modeli

> Sürüm: 1.0 — Migration `014_hq_chain` ile birlikte yayınlandı.

Bu döküman, GastroCore Go backend'ine eklenen "merkez (HQ) zincir restoran" mantığını anlatır. Amaç, çoklu lokasyona sahip bir restoran zincirinin tek bir merkezden ortak menüyü yönetmesini, lokasyonlara fiyat/içerik kilidi uygulayabilmesini ve toplam ciroyu çapraz raporlayabilmesini sağlamaktır.

---

## 1. Hiyerarşi

```
Organization (HQ)
   │
   ├── master tenant   (HQ menüsünün yazıldığı sanal restoran)
   │
   └── organization_memberships
         ├── Tenant A   (gerçek restoran #1)
         ├── Tenant B   (gerçek restoran #2)
         └── Tenant C   (...)
```

- **Organization**: Var olan `organizations` tablosu (002_multi_store) genişletildi (`owner_user_id`, `settings_json`).
- **Master Tenant**: HQ menüsünü düzenlemek için `is_master = TRUE` ile işaretlenmiş özel bir `tenants` satırı. İlk publish çağrısında otomatik oluşturulur.
- **Member Tenants**: HQ'ya bağlı her gerçek restoran. `organization_memberships` join tablosuyla bağlanır.

---

## 2. Yeni Migration

`migrations/014_hq_chain.up.sql` dosyası şu değişiklikleri yapar:

| Değişiklik | Açıklama |
|---|---|
| `organizations` ALTER | `owner_user_id`, `settings_json` eklendi |
| `organization_memberships` (yeni) | (organization_id, tenant_id, joined_at, is_master) |
| `menu_policies` (yeni) | Ürün başına lock semantiği |
| `master_menus` (yeni) | Org başına `current_version` pointer |
| `master_menu_versions` (yeni) | HQ snapshot history |
| `users` ALTER | `organization_id`, `org_role` eklendi |
| `menu_versions` (yeni veya kolon ekleme) | Per-tenant snapshot tablosu (paralel görevle uyumlu, additive) |

Geri alma: `014_hq_chain.down.sql` mevcut. Backfill: `tenants.organization_id` zaten dolu olan kayıtlar `organization_memberships`'a aktarılır.

---

## 3. Endpoint Listesi

Tümü `/api/v1/org/...` prefix'inde. JWT zorunlu (global gateway ile). `:orgId` path parametresi kullanıcının `users.organization_id`'si ile eşleşmek zorunda.

### Self
- `GET    /api/v1/org/me` — kimlik + org + üye restoranlar

### Restaurants (HQ admin görünümü)
- `GET    /api/v1/org/:orgId/restaurants` — üye listesi (ad, son aktivite, bugünkü ciro)
- `POST   /api/v1/org/:orgId/restaurants` — yeni restoran oluştur veya bağla
- `DELETE /api/v1/org/:orgId/restaurants/:restaurantId` — bağlantıyı kaldır (tenant silinmez)

### Master Menu CRUD
- `GET    /api/v1/org/:orgId/master-menu` — categories + products + modifier_groups snapshot
- `POST   /api/v1/org/:orgId/master-menu/categories`
- `PUT    /api/v1/org/:orgId/master-menu/categories/:id`
- `DELETE /api/v1/org/:orgId/master-menu/categories/:id`
- `POST   /api/v1/org/:orgId/master-menu/products` (opsiyonel inline `lock_type`)
- `PUT    /api/v1/org/:orgId/master-menu/products/:id`
- `DELETE /api/v1/org/:orgId/master-menu/products/:id`
- `POST   /api/v1/org/:orgId/master-menu/publish` — yeni master version + tüm üye restoranlara push

### Policies
- `GET    /api/v1/org/:orgId/policies`
- `POST   /api/v1/org/:orgId/policies`
- `PUT    /api/v1/org/:orgId/policies/:policyId`
- `DELETE /api/v1/org/:orgId/policies/:policyId`

### Reports
- `GET    /api/v1/org/:orgId/reports/aggregate?from=&to=` — tüm restoranların toplam ciro, en çok satan, lokasyon karşılaştırma
- `GET    /api/v1/org/:orgId/reports/by-restaurant?from=&to=` — restoran bazlı breakdown

---

## 4. Role Matrix

`users.org_role` alanında veya JWT `role` claim'inde aşağıdaki değerler:

| Rol | İzinler |
|---|---|
| `HQ_ADMIN`            | Tüm HQ endpoint'leri (restoran ekle/sil, policy CRUD, master menu CRUD, publish, reports) |
| `HQ_MANAGER`          | Restoran ekleme yapabilir, master menu düzenleyip publish edebilir, raporları görür. Restoran silme **HQ_ADMIN**'e özel. |
| `RESTAURANT_MANAGER`  | HQ endpoint'lerine erişemez. Kendi tenant'ı altında menü düzenleme; lock kuralları uygulanır. |
| `RESTAURANT_STAFF`    | Yalnızca okuma seviyesinde POS işlemleri. |
| `POS_OPERATOR`        | Cihaz bazlı sınırlı erişim. |

`requireRole` benzeri kontrol kalıbı: `m.hqOnly(...)` (HQ_ADMIN | HQ_MANAGER) ve `m.hqAdminOnly(...)` (HQ_ADMIN). Her handler kendi kontrolünü yapar; ek olarak orgId-mismatch ve user-no-org koruması vardır.

---

## 5. Lock Semantics

`menu_policies.lock_type` her HQ master ürünü için 3 değer alır:

| `lock_type`    | Restoran tarafında etkisi |
|---|---|
| `FULLY_LOCKED` | Restoran ürünü hiçbir şekilde değiştiremez. Update isteği `403 PRODUCT_LOCKED` döner. Soft-delete denemesi de reddedilir. |
| `PRICE_LOCKED` | `price`, `cost_price`, `tax_group` alanlarını değiştirme denemesi `403 PRODUCT_PRICE_LOCKED` döner. Diğer alanlar (isim, açıklama, görsel, display_order) serbestçe düzenlenebilir. `allow_local_disable=false` ise `is_active=false` denemesi de reddedilir. |
| `FLEXIBLE`     | Restoran ürünü tamamen düzenleyebilir. Master inheritance sırasında local override master'ı geçer. |

`menu_policies.allow_local_additions` ileride local-only ürün eklemeyi sınırlamak için ayrılmıştır (mevcut implementasyon her zaman izin verir).

Lock kontrolü `internal/org/policies.go`'daki `org.CheckMutation(ctx, db, Mutation{...})` ile yapılır. `internal/menu/handlers.go` içindeki `handleUpdateProduct` ve `handleDeleteProduct` bu çağrıyı yapar; HQ'ya bağlı olmayan tenant'lar için işlev no-op'tur.

Hata cevap şekli:
```json
{
  "code": "PRODUCT_LOCKED",
  "message": "Bu ürün HQ tarafından kilitli",
  "details": { "lock_type": "FULLY_LOCKED" }
}
```

---

## 6. Inheritance / Publish Akışı

`POST /api/v1/org/:orgId/master-menu/publish` çağrıldığında:

1. **Master snapshot inşası**: master tenant'ın `categories`, `products`, `modifier_groups`, `modifiers` tabloları okunur ve `MenuSnapshot` JSON'ına serileştirilir.
2. **Versiyonlama**: `master_menus.current_version + 1` hesaplanır; `master_menu_versions`'a yeni satır yazılır; `master_menus.current_version` ilerletilir.
3. **Per-tenant fan-out**: `organization_memberships` üzerinden tüm üye `tenant_id`'ler döner. Master tenant kendi snapshot'ını kullanır; diğerleri için her birinin local snapshot'ı çekilir.
4. **Merge**: `mergeMasterIntoLocal(master, local, policies)` `lock_type`'a göre alan-alan birleştirme yapar (yukarıdaki tabloya göre).
5. **Per-tenant version**: her üye için `MAX(version)+1` hesaplanır; `menu_versions`'a `source='master'`, `organization_id`, `master_version` doldurularak yeni satır eklenir.
6. **Bildirim**: `sync.Hub.NotifyTenant(tenantID, ...)` çağrılır → mevcut WebSocket pipeline POS / KDS cihazlarına yeni menünün yayınlandığını duyurur.

> Not: Stack tanımında Redis 7 var; ancak Go tarafında Redis client bağımlılığı yok. "menu:published:" pub/sub yerine var olan `sync.Hub` WebSocket köprüsü kullanılır. Redis hattı eklenmek istenirse `internal/sync/hub.go`'ya köprü eklemek yeterli olur — `org` modülü zaten hub'ı dependency-inject olarak alıyor.

---

## 7. HQ Snapshot Şekli

Master snapshot'ta ek alanlar:

```jsonc
{
  "organization_id": "uuid",
  "version": 5,
  "source": "master",                  // "master" | "local"
  "master_version": 5,                 // per-tenant satırlarda
  "categories": [...],
  "products": [
    {
      "id": "uuid",
      "name": "Latte",
      "price": 500,
      "lock_type": "PRICE_LOCKED",     // policy'den geldi
      "is_master": true,                // HQ'dan inherit edildi
      "local_only": false               // lokasyonun kendi eklediği ürün
    }
  ],
  "modifier_groups": [...],
  "generated_at": "2026-04-29T08:00:00Z"
}
```

Bu yapı `server/docs/menu-sync/CONTRACT.md`'deki temel snapshot şeklini extend eder. Geriye uyumlu — HQ'ya bağlı olmayan tenant'lar için ek alanlar boş bırakılır.

---

## 8. Aggregate Reports

`GET /reports/aggregate?from=&to=` döner:

```jsonc
{
  "organization_id": "...",
  "from": "...", "to": "...",
  "total_revenue": 12345600,
  "order_count": 1234,
  "avg_ticket": 10005,
  "restaurant_count": 4,
  "top_products": [
    { "product_id": "...", "product_name": "Latte", "quantity": 312.0, "revenue": 156000 }
  ],
  "comparison": [
    { "tenant_id": "...", "name": "Zürih Şube", "value": 4500000 },
    { "tenant_id": "...", "name": "Cenevre Şube", "value": 3000000 }
  ]
}
```

Sorgular `tickets.tenant_id = ANY($1::uuid[])` ile tüm üye `tenant_id`'leri tarar. `tickets.status='closed'` ve `is_deleted=FALSE` filtresi uygulanır. `order_items` üzerinden `product_id`/`product_name` rollup'ı yapılır.

`GET /reports/by-restaurant?from=&to=` her restoran için `revenue`, `order_count`, `avg_ticket`, `top_product` alanlarıyla satır listesi döner.

Tarih parametreleri RFC3339 veya `YYYY-MM-DD`. Belirtilmezse son 30 gün.

---

## 9. Test ve Doğrulama

`internal/org/handlers_test.go` ve `internal/org/publish_test.go` dosyaları:

- Auth path: `UNAUTHORIZED`, `ORG_MISMATCH`, `FORBIDDEN`
- `/me`: org-suz user
- Policy CRUD: happy path + bad lock_type
- `CheckMutation`: FULLY_LOCKED tüm değişimleri keser; PRICE_LOCKED price diff'i keser, cosmetic'i geçirir; FLEXIBLE her şeye izin verir; org üyesi olmayan tenant pass eder
- `mergeMasterIntoLocal`: FULLY_LOCKED master galip; PRICE_LOCKED master fiyat + local cosmetic; FLEXIBLE local galip; local-only ürün korunur
- **Kritik**: `TestHandlePublishMasterMenu_FanOutToAllMembers` — publish'in 2 üyeli bir org'da master_menu_versions + master_menus update + per-tenant menu_versions × 2 yazma sırasını doğrular.

`go test ./internal/org/...` ile çalıştırılır. `sqlmock` kullanılır; canlı DB gerekmez.

---

## 10. Paralel Görev Etkileşimi

`local_f868a3fa` paralel görevi `menu_versions` tablosunu ve `/api/v1/menu/...` altında snapshot/publish endpoint'lerini ekler. Bu modülle çakışma yok:

- `/api/v1/org/...` HQ-scoped, `/api/v1/menu/...` tenant-scoped.
- `master_menu_versions` org-level, `menu_versions` per-tenant.
- HQ publish, paralel görev tarafından yazılan `menu_versions` tablosunu **kullanır** (yeni satır ekler). Eğer paralel görev daha geç gelirse, bu migration tabloyu `IF NOT EXISTS` ile oluşturur ve her iki taraf da güvenle koşar. `source`, `organization_id`, `master_version` kolonları `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` ile additive — paralel migration'ı bozmaz.

Migration numarası 014 — 013 paralel görev tarafından alındığı için bu migration 014'e kaydırıldı. Paralel görev `menu_versions` tablosunu kendi şemasıyla oluşturur; bu migration `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` ile `source`, `organization_id`, `master_version` kolonlarını additive olarak ekler. Tablo yoksa (paralel görev gelmeden uygulanırsa) `CREATE TABLE IF NOT EXISTS` fallback'i devreye girer.

---

## 11. Bilinen Sınırlamalar / İlerideki İşler

- `allow_local_additions` policy alanı şu an enforce edilmiyor (her zaman serbest). Yeni-ürün ekleme akışında `org.CheckMutation` çağrısı eklenmeli (`Mutation{IsBulkInsert: true}` zaten field hazır).
- `mergeMasterIntoLocal` modifier seviyesinde merge yapmaz; modifier_group inheritance master-wins-on-id, local-only-keep prensibinde. İhtiyaç olduğunda derinleştirilmeli.
- Master tenant için JWT issuance flow'u henüz `org_role` alanını okumuyor; `internal/auth` tarafında bir login endpoint'i eklendiğinde DB'den `users.org_role` çekilip `Claims.Role`'a basılmalı. Şu an `org` modülü hem JWT claim'ini hem DB'yi kontrol ettiği için eksiklik fonksiyonel değil.
- Redis pub/sub: stack'te Redis 7 var, ama Go istemcisi yok. `sync.Hub` WebSocket aynı amaca hizmet ediyor; Redis köprüsü ileride opsiyonel eklenebilir.

---

## 12. Hızlı Kullanım Akışı

```bash
# 1. Migration
psql ... -f server/migrations/014_hq_chain.up.sql

# 2. HQ admin user yarat (mevcut /api/v1/users veya manuel SQL):
# UPDATE users SET organization_id = '<org-uuid>', org_role = 'HQ_ADMIN' WHERE id = '<user-uuid>';

# 3. Login → JWT al

# 4. Master menüye kategori/ürün ekle
curl -H "Authorization: Bearer $TOKEN" -X POST \
  /api/v1/org/$ORG/master-menu/categories \
  -d '{"name":"İçecekler","display_order":0,"is_active":true}'

# 5. Lock policy ekle (örn. logo ürünü için fiyat kilidi)
curl -H "Authorization: Bearer $TOKEN" -X POST \
  /api/v1/org/$ORG/policies \
  -d '{"product_id":"<pid>","lock_type":"PRICE_LOCKED"}'

# 6. Publish
curl -H "Authorization: Bearer $TOKEN" -X POST \
  /api/v1/org/$ORG/master-menu/publish

# 7. Cevap: { "master_version": 1, "published_to": N, "pushed_tenant_ids": [...] }
```
