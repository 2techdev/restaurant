# GastroCore POS — Stitch Design Brief V2 (Complete Redesign)

## Proje Hakkinda
GastroCore, Isvicre ve Almanya pazari icin offline-first restoran POS platformu.
Android tabletlerde (10" landscape) calisacak. Dark theme, premium, hizli.

**Referans urunler:**
- OrderPin (ekran goruntuleri mevcut — temiz, modern, resimli menu, 3-tab yapisi)
- SambaPOS (fonksiyonel derinlik, ticket/table mantigi)
- Loyverse (sadelik, onboarding kolayligi)
- Square POS (premium his, minimal)

**Tasarim sistemi:** Precision POS Framework (mevcut DESIGN.md ekte)
- Dark theme: surfaceDim (#111319) taban
- "No-Line" kurali: border yok, surface hierarchy ile ayrim
- Gradient butonlar: #AFC6FF → #528DFF (135°)
- Text: #F0F0F5 primary, #8E8E9A secondary, #5A5A6A dim
- Minimum 44px touch target, 24px edge padding
- Font: Inter, Extrabold (800) fiyatlar/toplamlar icin

---

## EKRANLAR (Toplam 20 Ekran + 3 Dialog)

Her ekran icin: 10" tablet landscape (1920x1200 veya 1280x800) optimize.
Her ekranin hem light hem dark versiyonu olmasin (once dark oncelikli).

---

### S01 — PIN Login
**Amac:** Personel girisi, 4-6 haneli PIN ile hizli auth
**Layout:**
- Sol: Bos/logo alani
- Orta: GastroCore logo (gradient) + "Terminal ID: T-001" + personel listesi (avatar grid)
- Sag: 4 nokta PIN gosterge + 3x4 numpad (64px tuslar)
**Elementler:**
- Personel avatar'lari: yuvarlak, isim altinda, secili olan yesil halka
- PIN tuslari: surfaceContainerHigh bg, basinca scale(0.97) + accent renk
- "GIRIS" butonu: gradient mavi
- Alt: "GastroCore v0.1.0" + tarih/saat
**Referans:** Mevcut screenshot'ta gorunuyor ama daha premium olmali

### S02 — Shift Opening (Vardiya Acma)
**Amac:** Kasada ne kadar para var, vardiyayi baslat
**Layout:**
- Merkezde tek kart
- Ust: Tarih + saat + kullanici bilgisi
- Orta: "Acilis Kasasi" label + buyuk para girisi (numpad)
- Alt: Hizli tutar butonlari (200 / 500 / 1000) + "VARDIYAYI BASLAT" gradient buton
**Notlar:** Sade, hizli, 10 saniyede gecilmeli

### S03 — Home Dashboard
**Amac:** Ana giris noktasi, modul secimi (2TECH FSR stili)
**Layout:**
- Ust bar: Logo + kullanici adi + shift badge (yesil "SHIFT OPEN") + tarih/saat
- Orta: 3x4 modul grid kartlari:
  Row 1: Order (yesil) | Order Records (turuncu) | Transactions (sari)
  Row 2: Cash Drawer (turuncu) | Customer (yesil) | Attendance (yesil)
  Row 3: Shift (turuncu) | Products (kirmizi) | Settings (mavi)
  Row 4: Back Office (mavi) | Report (kirmizi) | Lock Screen (gri)
- Her kart: ikon (48px) + label, surfaceContainerLow bg
- Alt bar: "2TECH" + version + "Sign out"
**Referans:** OrderPin'in ana menu ekrani gibi ama bizim 12 modul

### S04 — Order Center: Ongoing Tab
**Amac:** Aktif siparisleri gormek
**Layout:**
- Ust bar: ☰ (home) | **Ongoing** | Table | Menu | 🔍 | 🖨️ | [MA] ADMIN
- Alt ust: Filtre chips: All (3) | Dine In (2) | Takeaway (1)
- Ana alan: Siparis kartlari grid (3-4 sutun)
  - Her kart: tip badge (yesil "Dine In" / mavi "Takeaway") + siparis no (#0042) + misafir sayisi + toplam (CHF) + garson adi + gecen sure
  - Bos: "Aktif siparis yok" illustrasyon
**Referans:** OrderPin "Ongoing" ekrani

### S05 — Order Center: Table Tab
**Amac:** Masa durumlarini gormek, masadan siparis acmak
**Layout:**
- Ust bar: ayni (Table tab aktif, mavi alt cizgi)
- Alt ust: Filtre chips: All (14) | Available (10) | Occupied (3) | Unpaid (1)
  - Her chip renk kodlu: bos=gri, dolu=yesil, onaysiz=turuncu, odenmemis=kirmizi
- Sol sidebar (~120px): Kat listesi (Ana Salon (10), Teras (4))
- Ana alan: Masa kartlari grid
  - Her masa: numara (buyuk), kapasite ikonu, durum rengi (bos=koyu gri, dolu=yesil border, odenmemis=kirmizi border)
  - Dolu masalarda: siparis tutari + garson adi
**Referans:** OrderPin "Table" ekrani ama daha zengin bilgi

### S06 — Order Center: Menu Tab (ANA SIPARIS EKRANI)
**Amac:** Siparis alma — EN ONEMLI EKRAN, en cok kullanilacak
**Layout 3 sutun:**
- SOL (~140px): Kategori sidebar
  - "All" (aktif = accent sol cizgi)
  - Pizza, Burger, Kebab, Salata, Tatli, Icecek...
  - Sadece text, secili olan accent renkli
- ORTA (esnek): Urun grid
  - Ust: "Menu" label + arama + ⚙️ (display settings)
  - Grid: Urun kartlari
    - RESIMLI MOD: Resim alani (ust 60%) + isim + fiyat (alt 40%)
    - RESIMSIZ MOD: Renkli etiket kart, isim + fiyat ortada
    - KUCUK MOD: 5 sutun, kompakt
    - BUYUK MOD: 3 sutun, genis
  - Fiyat formati: Tek fiyat "CHF 18.00" veya aralik "12.00~22.00"
- SAG (~320px): Siparis paneli
  - Ust: Siparis turu dropdown (Dine-In ▼ / Takeaway / Delivery) + Meal # + ≡
  - Bos ise: Sepet illustrasyon + "Please select a product"
  - Dolu ise: Urun listesi (isim + qty [-][2][+] + fiyat + swipe-to-delete)
  - Alt: "Total (3 Items) CHF 42.00" + "Order" (yesil) + "Check out" (gradient mavi)
**Referans:** OrderPin "Menu" ekrani — bu ekranin mukemmel olmasi lazim!

### S07 — Menu Settings Dialog
**Amac:** Menu gorunumunu ayarla
**Layout:** Modal overlay, merkezde kart
- "Settings" baslik
- Button size: Big / Small (radio)
- Display: Picture / Color label (radio)
- Show weighing module: Yes / No (radio) — tartili urun
- Show price: Yes / No (radio)
- Sort: Default / Sales / Alphabetical (radio)
- Cancel + Confirm butonlari
**Referans:** OrderPin settings dialog screenshot'i

### S08 — Modifier / Addon Dialog
**Amac:** Urun opsiyonlari secimi (boyut, ekstralar, sos, pisirme)
**Layout:** Bottom sheet veya modal
- Ust: Urun adi (buyuk) + taban fiyat (yesil) + X kapat
- Her modifier grubu:
  - Grup adi + "ZORUNLU" badge (kirmizi, eger required)
  - Opsiyonlar: yatay scroll chips
    - Tek secim: radio stili (secili = accent border)
    - Coklu secim: toggle stili (secili = accent bg)
    - Her chip: isim + fiyat farki ("+CHF 2.00")
- Miktar: [-] [1] [+]
- Not alani: text input "Ozel not ekleyin..."
- Alt: "TOPLAM: CHF 42.00" (canli hesaplama) + "Iptal" + "Siparise Ekle" (gradient)

### S09 — Dining Options Dialog
**Amac:** Siparis turunu sec
**Layout:** Kucuk modal
- "Dining Options" baslik + X kapat
- 3 secenek (radio):
  - ○ Dine In
  - ● Takeout (secili = mavi)
  - ○ Delivery
**Referans:** OrderPin "Dining Options" screenshot'i

### S10 — Payment Screen
**Amac:** Odeme al
**Layout 2 sutun:**
- SOL (~35%): Siparis ozeti
  - Urun listesi (isim + qty + fiyat)
  - Ara toplam / KDV / Toplam
  - Yazdir + Iptal butonlari
- SAG (~65%): Odeme
  - Odeme yontemi secici: Nakit / Kredi / Banka / Bol Ode (4 buton)
  - Buyuk yesil tutar gosterge
  - Numpad + hizli tutar butonlari (10, 20, 50, 100)
  - Para ustu hesaplama
  - "ODEMEYI TAMAMLA" gradient buton

### S11 — Receipt Preview
**Amac:** Fis onizleme (termal yazici stili)
**Layout:**
- Koyu bg uzerinde beyaz fis karti (380px, ortada, golge/glow)
- Fis icerigi: restoran adi + adres + tarih + garson + urunler + toplam + odeme + "Afiyet Olsun!"
- Alt: "Yazdir" (gradient) + "E-Posta" + "Kapat"

### S12 — Split Bill
**Amac:** Adisyonu bol
**Layout:**
- Ust: "Split Bill" + Table 12 badge + toplam
- 3 tab: Urun Bazli / Esit Bol / Ozel Tutar
- Urun bazli: Sol "Master Bill" + sag "Bill 1", "Bill 2" kartlari
- Esit bol: Misafir sayisi [-][3][+] + "Kisi basina CHF 42.00"
- Alt: "Settle All Bills" gradient buton

### S13 — Shift Close / Z-Report
**Amac:** Vardiya kapat, kasa say, mutabakat
**Layout 2 sutun:**
- SOL (~60%): Vardiya ozeti
  - Hero toplam satis (buyuk yesil sayi)
  - 3 stat kart (siparis sayisi, ortalama, misafir)
  - Odeme yontemi dagilimi (ikonlu liste)
  - Void/indirim ozetleri
- SAG (~40%): Mutabakat
  - Kasa sayim girisi (numpad)
  - Beklenen vs sayilan karsilastirma
  - Fark gosterge (yesil "Tam" / kirmizi "Eksik" / turuncu "Fazla")
  - "VARDIYAYI KAPAT" gradient buton

### S14 — Refund / Iade
**Amac:** Iade islemi
**Layout 2 sutun:**
- SOL: Orijinal siparis (checkbox'lu urun listesi)
- SAG: Iade ozeti (secilen urunler + toplam kirmizi + neden dropdown + yonetici PIN uyarisi)
- "Iade Et" kirmizi buton

### S15 — Kitchen Display (KDS)
**Amac:** Mutfak ekrani, siparisleri hazirlama
**Layout:** Tam ekran, koyu bg, yesil vurgu
- Ust: KDS istasyon adi + vardiya + bekleyen/hazirlanan/tamamlanan sayaclari
- Ana: Yatay scroll ticket kartlari (280px genis)
  - Her ticket: masa/siparis no + gecen sure (timer) + urun listesi + modifier'lar (turuncu) + notlar (sari)
  - Renk kodlu kenar: yesil (<10dk), turuncu (<20dk), kirmizi (>20dk)
  - "HAZIR" bump butonu (buyuk, yesil)

### S16 — Back Office (4 Tab)
**Amac:** Menu/masa/personel yonetimi + raporlar
**Layout:**
- Sol sidebar (220px): 5 tab (Menu Yonetimi, Masa Duzenle, Personel, Raporlar, Ayarlar)
- Sag: Secili tab'in icerigi
**Alt ekranlar:**
- Menu: Kategori listesi (sol) + urun grid (sag) + CRUD dialog'lari
- Masa: Kat secici + masa grid + ekleme/duzenleme
- Personel: Staff kartlari + rol badge + PIN yonetimi
- Raporlar: Satis grafikleri + top 10 urun + odeme dagilimi

### S17 — Settings (7 Section)
**Amac:** Tum ayarlar
**Layout:**
- Sol sidebar (240px): 7 section (Restoran, Yazici, Vergi, Cihaz, Sync, Guvenlik, Hakkinda)
- Sag: Secili section'in form alanlari
- Her section'da "Kaydet" butonu

### S18 — Order History
**Amac:** Gecmis siparisler
**Layout:**
- Ust: Tarih filtresi + arama + filtre chips (Tumu/Acik/Tamamlanan/Iptal)
- Ana: Siparis kartlari listesi (siparis no + tarih + masa + toplam + durum badge)
- Tiklayinca: Detay expand (urunler + odeme + "Yeniden Yazdir" + "Iade")

### S19 — Online Order Acceptance (Gelecek)
**Amac:** Gelen online siparis kabul/red
**Layout:** Popup/overlay
- Yeni siparis bildirimi (ses + animasyon)
- Siparis detayi (urunler + toplam + musteri bilgisi)
- "Kabul Et" (yesil) + "Reddet" (kirmizi) + "Ertele" (turuncu)

### S20 — Device Pairing (Gelecek)
**Amac:** Yeni cihaz esleme
**Layout:**
- QR kod gosterimi (esleme kodu)
- Manuel kod girisi alani
- Eslenen cihazlar listesi

---

## DIALOGLAR

### D01 — Manager PIN Override
- "Yetki Gerekli" baslik + kilit ikonu
- Islem aciklamasi ("Void 2x Adana Kebap CHF 57.00")
- 4 nokta PIN girisi + mini numpad

### D02 — Confirm Dialog
- Baslik + mesaj + "Iptal" + "Onayla" butonlari
- Tehlikeli islemler icin kirmizi "Onayla"

### D03 — Discount Dialog
- Indirim turu: Yuzde / Sabit tutar
- Tutar girisi (numpad)
- Indirim adi (opsiyonel text input)
- Onizleme: "CHF 42.00 → CHF 37.80 (-%10)"

---

## NAVIGASYON AKISI

```
PIN Login (S01) → Shift Open (S02) → Home Dashboard (S03)
                                          |
                          +---------------+---------------+
                          |               |               |
                    Order Center     Back Office      Settings
                    (S04/S05/S06)      (S16)           (S17)
                          |
               +----------+----------+
               |          |          |
           Ongoing     Table      Menu
           (S04)       (S05)      (S06)
                                    |
                          +---------+---------+
                          |         |         |
                     Modifier   Dining    Payment
                     (S08)    Options(S09)  (S10)
                                              |
                                        +-----+-----+
                                        |           |
                                    Receipt    Split Bill
                                    (S11)       (S12)
```

---

## ONEMLI TASARIM NOTLARI

1. **10" tablet landscape** optimize — telefon degil
2. **Touch-friendly**: minimum 44px, tercihan 48px+ touch target
3. **Garson hizinda**: En sik islem (urun ekle) 1 tap'te olmali
4. **Karanlık ortam**: Restoran losu, goz yormamali
5. **Premium his**: Ucuz POS gibi degil, profesyonel yazilim gibi gorunmeli
6. **OrderPin kalitesi**: OrderPin screenshot'larina bakarak o seviyede veya daha iyi olmali
7. **Resimli menu**: Urun resimleri buyuk ve net, placeholder ise minimalist ikon
8. **Para birimi**: CHF (Isvicre Franki), . (nokta) ondalik ayirici
9. **Dil**: UI Ingilizce + Almanca karisik (ayarlanabilir olacak)
10. **Stitch Design System**: DESIGN.md'deki kurallara uymali (No-Line, surface hierarchy, gradient butonlar)
