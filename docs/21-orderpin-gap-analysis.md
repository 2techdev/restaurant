# OrderPin API Gap Analysis — GastroCore İçin Eksik/İyileştirilecek Noktalar

**Kaynak:** OrderPin OpenAPI PDF (55 sayfa)
**Tarih:** 2026-03-20

---

## 1. ÖZET

OrderPin, production seviyede bir restoran POS platformu. API'leri incelediğimizde GastroCore'da şu alanlarda eksik veya iyileştirme ihtiyacı var:

| Alan | GastroCore Durumu | OrderPin'de Var | Öncelik |
|------|-------------------|-----------------|---------|
| SPU/SKU ürün modeli | Yok (tek fiyatlı product) | ✅ Tam SPU/SKU | 🔴 Yüksek |
| Fare (ücret) hesaplama motoru | Basit (subtotal+tax) | ✅ 15+ kalem detaylı | 🔴 Yüksek |
| Service fee / Package fee / Delivery fee | Yok | ✅ Ayrı kalemler | 🟡 Orta |
| Special discount (özel indirim) | Basit discount | ✅ İsimli, vergi-bağlantılı | 🟡 Orta |
| Vergi indirimi bağlantısı (is_discounted) | Yok | ✅ İndirimde vergi dahil/hariç | 🔴 Yüksek |
| Round-down (yuvarlama silme) | 5 Rappen sadece | ✅ Çoklu yuvarlama kuralı | 🟡 Orta |
| Stok yönetimi (in_stock/out_of_stock) | Yok (active/inactive) | ✅ Detaylı stok durumu | 🟡 Orta |
| detail_status (out_of_stock_today) | Yok | ✅ Gün sonunda otomatik reset | 🟢 Düşük |
| CRM / Müşteri yönetimi | Entity var, UI yok | ✅ Tam CRUD + sipariş ilişki | 🟡 Orta |
| Müşteri-sipariş ilişkilendirme | Yok | ✅ associate_order | 🟢 Düşük |
| Müşteri etiketleme (tags) | Yok | ✅ Kategori bazlı etiket | 🟢 Düşük |
| Sipariş kaynağı (origin) | channel alanı var | ✅ e-menu/disoo/merchant | ✅ Var |
| food_back (yemek iade/geri alma) | void item olarak var | ✅ Ayrı endpoint | ✅ Benzer |
| Split checkout (bölünmüş ödeme) | split_bill ekranı var | ✅ Detaylı API | ✅ Var |
| Pickup code (paket kodu) | Yok | ✅ Otomatik üretim | 🟡 Orta |
| Tartılı ürün (weight dishes) | Yok | ✅ is_weight_dishes + weight_unit | 🟡 Orta |
| Open price (mevsimlik/serbest fiyat) | Yok | ✅ is_open_price | 🟡 Orta |
| Online ödeme entegrasyonu | Yok (Phase 6) | ✅ online_payment ayrı blok | 🟢 Sonra |
| QR code ödeme kanalları | Yok | ✅ qr_code_channel_list | 🟢 Sonra |
| 3. parti platform entegrasyonu | Yok | ✅ third_party (ALIPAY, BOOST) | 🟢 Sonra |
| İş saatleri (business_time) | Yok | ✅ Gün bazlı açılış/kapanış | 🟡 Orta |
| Mağaza lokasyon/koordinat | Yok | ✅ latitude/longitude | 🟢 Düşük |
| Payment kanalı toplama bilgisi | Yok | ✅ is_collect_payment_info | 🟢 Düşük |
| Kupon sistemi (coupon_total) | Yok | ✅ Sipariş içinde kupon | 🟢 Sonra |
| Geçici ücretler (temporary_charge) | Yok | ✅ Checkout anında eklenen | 🟡 Orta |

---

## 2. KRİTİK EKSİKLER (Hemen Düzeltilmeli)

### 2.1 SPU/SKU Ürün Modeli

**OrderPin:** Her ürün SPU (Standard Product Unit) ve altında SKU'lar (varyantlar) var.
- `spu_id` + `spu_name` → Ana ürün (ör: "Burger")
- `sku_id` + `sku_name` → Varyant (ör: "Büyük Burger", "Küçük Burger")
- Her SKU'nun kendi fiyatı var
- `spec` → Spesifikasyon bilgisi (single/multi)

**GastroCore:** Tek seviye `Product` + ayrı `ModifierGroup/Modifier`.

**Öneri:** SPU/SKU modeli DAHA GÜÇLÜ çünkü:
- Farklı boyutlar farklı fiyat olabiliyor (Küçük Pizza 15 CHF, Büyük Pizza 22 CHF)
- Şu an bunu modifier price_delta ile yapıyoruz ama bu "price_delta" yaklaşımı doğru değil
- SKU modeli: her varyant bağımsız fiyata sahip, stok takibi SKU bazında

**Aksiyon:** Product entity'ye `sku_id`, `spec_type` alanları ekle. Veya Product'ı SPU, SKU alt entity ekle.

### 2.2 Fare (Ücret) Hesaplama Motoru

**OrderPin'in fare (ücret) yapısı:**
```
fare:
  dishes_origin_total      → Orijinal yemek toplamı (indirim öncesi)
  dishes_total_pre_tax     → Yemek toplamı (vergi öncesi)
  dishes_total             → Yemek toplamı (vergi dahil)
  dishes_taxes[]           → Yemek vergileri (birden fazla vergi oranı)
  additional_cost_total    → Ek masraflar toplamı
  additional_costs[]       → Ek masraf listesi (her birinde vergi bilgisi)
  service_fee              → Servis ücreti (vergi dahil/hariç seçenekli)
  package_fee              → Paketleme ücreti
  delivery_fee             → Teslimat ücreti
  discount_total           → İndirim toplamı (vergi dahil)
  special_discount_total   → Özel indirim toplamı
  coupon_total             → Kupon tutarı
  round_down_total         → Yuvarlama silme
  receivable_total         → Tahsil edilecek toplam
  pay_total                → Ödenen toplam
  change_total             → Para üstü
  refund_total             → İade toplamı
  unpaid_total             → Ödenmemiş toplam
  temporary_charge_total   → Geçici ücretler
```

**GastroCore'un fare yapısı:**
```
ticket:
  subtotal     → Ara toplam
  tax_amount   → Vergi
  discount     → İndirim
  total        → Toplam
```

**FARK ÇOK BÜYÜK.** OrderPin 15+ kalem fare hesabı yapıyor, biz 4 kalem.

**Aksiyon:** Fare hesaplama motorunu genişlet:
- `service_fee`, `package_fee`, `delivery_fee` ayrı alanlar ekle
- `special_discount` listesi (isimli indirimler)
- Vergi hesabında `is_discounted` flag'i (indirim vergiye etki eder mi?)
- `round_down_total` yuvarlama silme
- `receivable_total` hesaplama formülü OrderPin'den al

### 2.3 Vergi-İndirim Bağlantısı

**OrderPin:** Her vergi kaleminde `is_discounted` flag'i var.
- `true` → İndirim vergi tutarını da etkiler
- `false` → İndirim sadece fiyatı etkiler, vergi tam kalır

**GastroCore:** Bu ayrım yok. İndirim flat olarak uygulanıyor.

**Aksiyon:** TaxRate entity'ye `is_discountable` flag ekle. Vergi hesaplama motorunda bunu kontrol et.

---

## 3. ÖNEMLİ EKSİKLER (Yakında Eklenmeli)

### 3.1 Stok Durumu Yönetimi

**OrderPin stok durumu:**
- `status`: in_stock / out_of_stock
- `detail_status`: in_stock / out_of_stock_today / delisted
- `out_of_stock_today`: Gün sonunda (mağaza ülkesinin gece yarısı) otomatik `in_stock` olur

**GastroCore:** Sadece `is_active` boolean.

**Aksiyon:** Product'a `stock_status` enum ekle: `in_stock`, `out_of_stock`, `out_of_stock_today`, `delisted`. Günlük reset mekanizması ekle.

### 3.2 Service Fee / Package Fee / Delivery Fee

**OrderPin:** Her biri ayrı hesaplanan ücret:
- `service_fee`: Sabit tutar veya sipariş tutarının yüzdesi
  - `taken_type`: fixed_amount / order_amount_ratio_round / _ceil / _floor
  - `is_taxable`: Vergi uygulanır mı
  - `order_types`: Hangi sipariş türlerinde geçerli (dine-in, takeaway, delivery)
- `package_fee`: Paketleme ücreti (takeaway/delivery'de)
- `delivery_fee`: Teslimat ücreti

**Aksiyon:** Ticket entity'ye şu alanları ekle:
```
service_fee_amount    INTEGER DEFAULT 0
package_fee_amount    INTEGER DEFAULT 0
delivery_fee_amount   INTEGER DEFAULT 0
```
Settings'te service fee hesaplama kurallarını yapılandır.

### 3.3 Pickup Code (Paket Kodu)

**OrderPin:** Her takeaway siparişte `pick_up_code` var. Müşteriye verilen numara.

**GastroCore:** Yok.

**Aksiyon:** Takeaway sipariş oluşturulduğunda otomatik 3-4 haneli pickup kodu üret. KDS'te ve fişte göster.

### 3.4 Open Price (Serbest Fiyat)

**OrderPin:** `is_open_price: true` → Garson fiyatı elle girer (mevsimlik yemek, özel sipariş)

**GastroCore:** Yok.

**Aksiyon:** Product'a `is_open_price` flag ekle. POS ekranında bu ürün seçildiğinde fiyat giriş numpad'i göster.

### 3.5 Tartılı Ürün (Weight Dishes)

**OrderPin:**
- `is_weight_dishes: true`
- `weight`: Tartılan ağırlık
- `weight_unit`: kg/g/lb
- `weight_sale_price`: Birim fiyat
- Toplam = weight × weight_sale_price

**GastroCore:** Yok (market modu için zaten planlanmıştı).

**Aksiyon:** Product'a `is_weight_based`, `weight_unit` ekle. Phase 10 (Retail) için zaten hazırlık yapmış oluruz.

### 3.6 İş Saatleri (Business Hours)

**OrderPin:**
```json
business_time: [
  { type: "monday", hours: [{ start_at: "09:00", end_at: "23:00" }] },
  { type: "tuesday", hours: [...] }
]
```

**Aksiyon:** Tenant/Branch entity'ye `business_hours_json` JSONB alanı ekle. Online sipariş ve QR menüde "kapalıyız" mesajı göster.

### 3.7 Yuvarlama Kuralları (Rounding)

**OrderPin çok detaylı:**
- `rule`: floor (aşağı) / round (yakına) / ceil (yukarı)
- `unit`: percentile (kuruş) / five_percent (5 kuruş) / tenths / units / tens / hundreds

**GastroCore:** Sadece 5 Rappen yuvarlama.

**Aksiyon:** Settings'te yuvarlama kuralı yapılandırması ekle. Country pack'te varsayılan ayarla.

### 3.8 Ödeme Kanalı Detayları

**OrderPin her ödeme kaydında:**
- `pay_channel`: cash / Online / credit_card / etc.
- `pay_sub_channel`: GHL:ECR, H2H gibi alt kanallar
- `payment_form`: Scan / card insert / card swipe
- `payment_no`: Barkod, QR kod, kart numarası (maskelenmiş)
- `external_payment_id`: 3. parti ödeme referansı
- `external_channel`: ALIPAY, BOOST gibi

**GastroCore:** Sadece `payment_method` (cash/credit_card/debit_card/other).

**Aksiyon:** Payment entity'ye şu alanları ekle:
```
pay_sub_channel    TEXT
payment_form       TEXT
payment_reference  TEXT    -- kart referansı / QR kodu
external_channel   TEXT    -- 3. parti kanal
external_payment_id TEXT   -- 3. parti ödeme ID
```

---

## 4. NİCE-TO-HAVE EKSİKLER (İleride)

### 4.1 CRM Müşteri Yönetimi
- OrderPin'de tam CRUD + sipariş ilişkilendirme + etiketleme + dışa aktarma var
- GastroCore'da Customer entity var ama UI ve aktif kullanım yok
- **Aksiyon:** Phase 6+ (Online ordering ile birlikte)

### 4.2 Kupon Sistemi
- OrderPin'de `coupon_total` fare hesabına dahil
- **Aksiyon:** Phase 3+ (Cloud sync sonrası)

### 4.3 Online Ödeme (Alipay, QR Code, vb.)
- OrderPin'de `online_payment` ayrı blok, `qr_code_channel_list` var
- **Aksiyon:** Phase 6+ (Online ordering ile birlikte)

### 4.4 Cashier Name Tracking
- OrderPin her checkout kaydında `cashier_name` tutuyor
- **Aksiyon:** Payment entity'ye `cashier_name` ekle (kolay, hemen yapılabilir)

### 4.5 Sipariş İptali Nedeni
- OrderPin'de `order_cancel_reason` → `reason_enum` + `reason_message`
- **Aksiyon:** Ticket entity'ye `cancel_reason` TEXT ekle

---

## 5. GastroCore'DA ORDERPIN'DE OLMAYAN ŞEYLER (BİZİM AVANTAJIMIZ)

| Özellik | GastroCore | OrderPin |
|---------|-----------|----------|
| Offline-first mimari | ✅ Tam offline | ❌ Cloud bağımlı |
| Masaüstü KDS | ✅ Ayrı tablet app | ❌ API üzerinden |
| Vardiya/Kasa yönetimi | ✅ Tam shift lifecycle | ❌ API'de yok |
| Cash movement (pay-in/pay-out) | ✅ Detaylı | ❌ Yok |
| Floor plan görsel editör | ✅ Drag-drop | ❌ Sadece grup/numara |
| Almanya fiskal (TSE/Fiskaly) | ✅ Planlandı | ❌ Yok |
| İsviçre KDV + QR-bill | ✅ Planlandı | ❌ Yok |
| ERPNext muhasebe köprüsü | ✅ Planlandı | ❌ Yok |
| Course yönetimi | ✅ Ateşle/beklet | ❌ Yok |
| Manager PIN override | ✅ Detaylı audit | ❌ Yok |
| Offline lisans modeli | ✅ Yıllık offline | ❌ Cloud zorunlu |

---

## 6. AKSİYON PLANI (Öncelik Sırasına Göre)

### 🔴 Sprint 2'de Yapılmalı (Fare motoru + SPU/SKU)
1. Fare hesaplama motorunu genişlet (service_fee, package_fee, delivery_fee, special_discount, round_down)
2. Vergi-indirim bağlantısı (is_discounted flag)
3. Payment entity'ye detaylı kanal bilgisi ekle
4. Stok durumu enum'u (in_stock / out_of_stock / out_of_stock_today)
5. Cancel reason alanı

### 🟡 Sprint 3'te Yapılmalı
6. Open price desteği
7. Pickup code üretimi (takeaway)
8. İş saatleri konfigürasyonu
9. Yuvarlama kuralları genişletmesi
10. Cashier name tracking

### 🟢 İleride Yapılmalı (Phase 6+)
11. SPU/SKU tam geçiş (veya mevcut Product+Modifier modelinin yeterliliği yeniden değerlendirilir)
12. CRM müşteri yönetimi UI
13. Kupon sistemi
14. Tartılı ürün desteği
15. Online ödeme kanalları
