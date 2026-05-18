# Customer-Facing Display (CFD) — POS integration spec

> Müşteri yan ekranı: POS tablette operatörün kayıt ettiği sepeti müşteri kendi tabletinden anlık görür. Lightspeed K-Series / Square Customer Display muadili. Pilot v1 hedefi.

**Live URL'ler (Reservation 178, 2026-05-17 gece deploy):**
- CFD ekranı: `https://gastro.2hub.ch/{slug}/cfd?device={deviceId}&lang={tr|de|en|fr|it}`
- Pair sayfası: `https://gastro.2hub.ch/{slug}/cfd/pair?device={deviceId}`
- Operatör tester: `https://gastro.2hub.ch/dashboard/cfd-tester` (admin auth ile)

## 1. Mimari

```
┌───────────┐  POST /api/cfd/state/<id>  ┌──────────────┐  SSE   ┌──────────────┐
│ POS app   │ ──────── push ──────────►  │ Reservation  │ ─────► │ CFD tablet   │
│ (Flutter) │                            │ Next.js 178  │        │ /cfd display │
└───────────┘                            └──────────────┘        └──────────────┘
       │                                        │                       │
       │ token (bearer)                         │ Redis: state+pub/sub  │ token (query)
       └────────────────────────────────────────┴───────────────────────┘
                       pair PIN handshake (one-shot)
```

CFD ve POS app arasında doğrudan bağ yok — Reservation backend aracı.
Cart state Redis'te (TTL 30 dk sliding), POS push'ları pub/sub ile SSE abonelerine fan-out edilir.

## 2. Pair flow (zorunlu, one-shot)

| Adım | Aktör | Çağrı |
|---|---|---|
| 1 | POS | `POST /api/cfd/pair/{deviceId}` (no auth) |
| 1r | Backend | `{ pin, token, expiresInSec: 300 }` döner. POS PIN'i ekranda gösterir, token'ı saklar. |
| 2 | Müşteri | CFD tablette `/{slug}/cfd/pair?device={deviceId}` aç → PIN gir |
| 3 | CFD | `POST /api/cfd/claim/{deviceId}` body `{pin}` |
| 3r | Backend | `{ token }` döner (PIN one-shot, tüketildi). CFD localStorage `cfd:token:{deviceId}` |
| 4 | CFD | Auto-redirect → `/{slug}/cfd?device={deviceId}` |
| 5 | CFD | SSE `GET /api/cfd/stream/{deviceId}?token={token}` |

PIN 5 dk, token 24 sa TTL. Token süresi dolarsa CFD `cfd:token:` localStorage'ı silinir → pair sayfasına bounce eder.

`deviceId` POS'un seçtiği herhangi bir string (4-64 char). Önerilen: cihaz pairing UUID + `-cfd` suffix (`abc123-cfd`) ya da random UUID per-pair.

## 3. Cart state push (POS → Reservation, her cart değişikliğinde)

```
POST https://gastro.2hub.ch/api/cfd/state/{deviceId}
Authorization: Bearer {token}
Content-Type: application/json

{
  "seq": 1715990400123,
  "restaurant": { "slug": "demo-restaurant", "name": "Demo Restaurant", "logoUrl": null },
  "locale": "tr",
  "lines": [
    {
      "id": "line-1",
      "name": "Pizza Margherita",
      "nameTranslations": { "de": "Pizza Margherita", "tr": "Pizza Margherita", "en": "Pizza Margherita" },
      "quantity": 1,
      "unitPriceCHF": 16.50,
      "totalCHF": 16.50,
      "modifiers": ["Klein", "extra Käse"],
      "isAlcoholic": false
    },
    { "id": "line-2", "name": "Bier 0.5L", "quantity": 2, "unitPriceCHF": 6.00, "totalCHF": 12.00, "isAlcoholic": true }
  ],
  "subtotalCHF": 28.50,
  "discountCHF": 0,
  "taxBreakdown": [
    { "rateLabel": "2.6%", "amountCHF": 0.42 },
    { "rateLabel": "8.1%", "amountCHF": 0.90 }
  ],
  "totalCHF": 28.50,
  "payment": { "phase": "idle" },
  "banner": null
}
```

**Push frequency:** her cart mutation (add/remove/qty/modifier/discount). Debounce ~150ms tavsiye edilir (rapid +/− tuş basışı için), aksi takdirde her keystroke push.

**Response:** `{ success: true, data: { seq, updatedAt } }`. 401 → token invalid (pair tekrar gerek). 400 → state shape eksik (`restaurant` ve `lines` zorunlu).

**Payment phase state-machine** (CFD farklı ekran açar):
- `idle` — normal cart preview
- `awaiting_card` — "💳 Lütfen kartınızı uzatın"
- `awaiting_twint` — "📱 TWINT QR okutun"
- `awaiting_cash` — "💰 Ödeme tamamlanıyor"
- `processing` — "Ödeme işleniyor…" (animated pulse)
- `success` — "✓ Teşekkür ederiz!" yeşil ekran (+tendered/change göster)
- `failed` — "✕ Tekrar deneyin" kırmızı ekran

Success'ten 5sn sonra POS tekrar `idle` + boş lines push etmeli → CFD "Hoş geldiniz" ekranına döner.

## 4. Endpoint özeti

| Method | Path | Auth | Açıklama |
|---|---|---|---|
| POST | `/api/cfd/pair/{deviceId}` | none | PIN üret + token döndür (POS) |
| POST | `/api/cfd/claim/{deviceId}` | none + PIN body | PIN tüket → token (CFD) |
| GET  | `/api/cfd/state/{deviceId}` | none | Mevcut state snapshot (debug / fallback poll) |
| POST | `/api/cfd/state/{deviceId}` | Bearer token | Cart push (POS) |
| GET  | `/api/cfd/stream/{deviceId}?token=…` | token query | SSE — `event: cart` her push'ta |

GET state public — deviceId zaten capability URL'i gibi (PIN handshake olmadan leak olmaz). POS-write side token'la gated, leaked deviceId tek başına display'i zehirleyemez.

## 5. SSE event şeması

```
event: connected
data: {"deviceId":"...","channel":"cfd:device:...:updates"}

event: cart
data: { ...CartState }       # her POS push'unda + bağlantı kuruluşta replay

: heartbeat                  # 25 sn'de bir keepalive (yorum satırı)
```

CFD ReadableStream reconnect on close — exponential backoff (1, 2, 4, 8, 16, 30 sn cap). `seq` monotonik — gelen daha düşük seq'i drop eder (re-order güvenliği).

## 6. POS app çağıracağı kod (Dart taslak)

```dart
class CfdClient {
  final String deviceId;
  final String baseUrl = 'https://gastro.2hub.ch';
  String? _token;

  Future<({String pin, String token})> initPair() async {
    final res = await http.post(Uri.parse('$baseUrl/api/cfd/pair/$deviceId'));
    final data = jsonDecode(res.body)['data'];
    _token = data['token'];
    return (pin: data['pin'], token: data['token']);
  }

  Future<void> push(CartState state) async {
    if (_token == null) return;
    await http.post(
      Uri.parse('$baseUrl/api/cfd/state/$deviceId'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(state.toJson()),
    );
  }
}
```

**POS UI entegrasyon:**
- Settings ekranında "Müşteri ekranı" tile → "Yeni pair PIN üret" butonu
- PIN üretildikten sonra QR olarak da göster (CFD pair URL'i + deviceId + PIN içerir → tek tıkla yönlenebilir)
- Cart provider'a listener: her değişiklikte `CfdClient.push()` (debounce 150ms)
- Payment flow state-machine'ine `phase` field ekle → her phase change'de push

## 7. Tester (POS olmadan demo)

`https://gastro.2hub.ch/dashboard/cfd-tester` (admin auth):
- `cfd-demo-01` deviceId default
- "PIN üret" → ekranda 6 hane göster
- Müşteri tablette `https://gastro.2hub.ch/demo-restaurant/cfd/pair?device=cfd-demo-01` aç, PIN gir
- Cart düzenleyici + payment phase selector + "Push → CFD" → display anında güncellenir
- Log paneli — push success/fail history

## 8. Smoke (2026-05-17 22:xx CEST, 178 canlı)

| Test | Sonuç |
|---|---|
| `GET /{slug}/cfd/pair` page | **200** ✓ |
| `POST /api/cfd/pair/{id}` | **200** + `{pin, token, expiresInSec: 300}` ✓ |
| `POST /api/cfd/claim/{id}` wrong PIN | **401 INVALID_PIN_OR_EXPIRED** ✓ |
| `GET /api/cfd/stream/{id}` no token | **401** ✓ |
| Reservation deploy CSS guard | **5/5 pass** ✓ (HTML no-store, CSS 200, palazzo+badi-bistro custom domain 200) |

## 9. Bilinmesi gerekenler

- **Redis zorunlu.** Reservation 178'de `gastro_redis` container çalışıyor (`REDIS_URL` env var). Redis down ise pair/state/stream sessiz fail eder (cache.ts try/catch swallows) — CFD "Bağlantı koptu" toast gösterir.
- **5 dil hardcoded** `cfd-display-client.tsx` ve `pair-client.tsx` içinde (next-intl Reservation public route'larda yok). DE/TR primary, EN/FR/IT mirror.
- **HTML cache header:** `Cache-Control: no-store, must-revalidate` — Cloudflare HTML'i cache'lemez (CSS regression guard fix May 9'dan beri).
- **PIN regen:** POS aynı deviceId için yeni `POST /api/cfd/pair` çağırırsa → eski PIN/token invalidate olur (cache key overwrite). Operatör "PIN yenile" yapabilir.
- **Display security:** GET state ve display URL public. deviceId rastgele üretilmeli (UUID), guess edilemez. Token leak ederse POS-push spoofable → POS yeniden pair yapar (yeni token).
- **Çoklu CFD:** bir POS birden fazla CFD'ye broadcast edebilir — farklı deviceId'lerle birden fazla pair yapılır, hepsine ayrı push. SSE doğal olarak çoklu subscriber destekler.

## 10. TODO (sonraki cycle)

- [ ] POS Flutter `CfdClient` + Settings UI + cart listener (jolly-final lineage, ayrı APK rebuild)
- [ ] QR pair flow — pair URL'i QR olarak göster, CFD tablette `?device&pin` query ile auto-claim
- [ ] Promo banner backoffice editor — happy_hour/upsell mesajlarını `banner.text`'e push
- [ ] Logo/theme — Restaurant tablosundan `logoUrl + primaryColor` çek ve initial state'e ekle (şu an POS push body'sinden alıyor)
- [ ] Multi-tenant POS push gateway: tek bir POS device çoklu CFD'ye paralel push (mevcut zaten destekler, UI dokümante yok)
