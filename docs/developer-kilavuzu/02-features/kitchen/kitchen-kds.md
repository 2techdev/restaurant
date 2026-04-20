# Kitchen / KDS

Mutfak ekranı. Kasiyer SENDEN'e bastığında gönderilen item'lar mutfakta duvar ekranında belirir.

**Dizinler**:
- `apps/pos/lib/features/kitchen/` - POS içindeki kitchen iş mantığı
- `apps/pos/lib/features/kds_app/` - Ayrı KDS flavor için feature'lar
- `apps/pos/lib/kds_app.dart` - KDS flavor root widget
- `apps/pos/lib/main_kds.dart` - KDS entry

## İki Rol

### POS flavor'da kitchen feature
Kasiyer tarafından "send to kitchen" eylemi burada tetiklenir. POS `KitchenTicket` yaratır, lokalde saklar, `SyncQueue` üzerinden cloud'a gönderir.

### KDS flavor
Ayrı bir APK. Mutfak duvarı ekranı. WebSocket ile cloud'dan `KitchenTicket` akışını dinler ve liste halinde gösterir.

## Entity

### `KitchenTicketEntity` (domain/entities/kitchen_ticket_entity.dart)
```dart
class KitchenTicketEntity {
  final String id;
  final String ticketId;               // parent ticket (POS'taki sepet)
  final String? tableLabel;            // "Tisch 5" vb
  final int? courseNumber;             // Gang 1 / 2 / 3
  final List<KitchenTicketItemEntity> items;
  final KitchenTicketStatus status;    // pending, preparing, ready, served
  final DateTime createdAt;
  final DateTime? preparedAt;
  final DateTime? servedAt;
}

class KitchenTicketItemEntity {
  final String productName;
  final int quantity;
  final List<String> modifierLabels;   // "Extra Käse", "Ohne Zwiebeln"
  final String? notes;
  final KitchenItemStatus status;
}
```

## DB Tabloları

- `KitchenTickets` - Kitchen ticket kayıtları
- `KitchenTicketItems` - Ticket item'ları (ürün, quantity, modifier'lar)
- `OrderGangStates` - Hangi course'un hangi stage'de olduğu

## POS Tarafı: Send to Kitchen

**`features/orders/presentation/providers/order_provider.dart` -> `sendToKitchen()`**

Akış:
1. Ticket'taki `sentToKitchen == false` item'lar filtrelenir.
2. Yeni `KitchenTicket` ID oluşur (UUID v4).
3. Kitchen ticket + item'lar DB'ye yazılır.
4. Parent ticket item'ları `sentToKitchen = true` işaretlenir.
5. `SyncQueue`'a push pending satırı eklenir.
6. UI SnackBar: "An die Küche gesendet".

Audio beep (opsiyonel): KDS ekranına ulaştığında ses çalar (`audioplayers` + `assets/audio/kds_new_ticket.wav`).

## KDS Tarafı: Display

`apps/pos/lib/features/kitchen/presentation/screens/kitchen_display_screen.dart` (POS flavor'da da erişilebilir).

KDS flavor'da bu ekran tam ekran açılır.

### `kitchen_provider.dart`

```dart
final kitchenTicketsStreamProvider = StreamProvider<List<KitchenTicketEntity>>((ref) {
  final ws = ref.watch(syncWebSocketProvider);
  return ws.stream
      .where((e) => e.type == 'kitchen_ticket')
      .map(_parseKitchenTicket)
      .scan(..., initialValue: []);
});
```

(Tam implementasyon sadece referans, gerçek koda bakın.)

### Durum renkleri (status by color)
- `pending` (yeni geldi) - Sari/amber
- `preparing` - Yesil border
- `ready` (bekliyor) - Mavi
- `served` - Gri (listeden kaldırılır)

Kitchen ticket grid'de 3-4 ticket yan yana gösterilir. Chef bir item'a dokunarak status'u değiştirir.

## Gang (Kurs) Sistemi

Fine dining modda item'lar kurslara ayrılır:
- Gang 1: Vorspeisen (starters)
- Gang 2: Hauptgang (main)
- Gang 3: Nachspeise (dessert)

Mutfak bir kurs bitip servis edildikten sonra bir sonraki kursu hazırlamaya başlar. `OrderGangStates` tablosu hangi kursun hangi aşamada olduğunu tutar.

POS tarafında `_GangTabs` widget'ı (`pos_v2_shell.dart:829`) kasiyerin item'ları kurslara ayırmasını sağlar.

## WebSocket Sync

`packages/gastrocore_sync/` içinde WebSocket bağlantısı kurulur. Cloud'dan gelen event'ler:
```json
{
  "type": "kitchen_ticket_created",
  "payload": { "id": "...", "ticketId": "...", "items": [...] }
}
```

KDS bu event'leri stream'ler, UI anlık günceller. POS da kendi gönderdiği event'in diğer KDS'lere iletildiğinden emin olur.

Fallback: WebSocket bağlanamazsa (kısa süreli offline) `/api/v1/sync/pull` ile polling.

## LAN Sync (WiFi İçi)

WAN (internet) olmasa bile POS ve KDS aynı WiFi'dayken birbirini görür.

`apps/pos/lib/features/lan_sync/`:
- `shelf` gömülü HTTP sunucusu (port 8787).
- `multicast_dns` ile mDNS keşfi (`_gastrocore._tcp.local.`).
- POS direkt `http://kds-device.local:8787/` adresine kitchen ticket gönderir.

Bu, restoranın internet bağlantısı kesildiğinde bile mutfak akışının devam etmesini sağlar.

## Void / Iptal

Kasiyer bir item'ı void ettiğinde:
1. Eğer item mutfağa gönderilmemişse (`sentToKitchen == false`) - sadece local silme.
2. Gönderilmişse -> `storno_log_provider`'a kayıt, KDS'ye "cancel" event gider, mutfak ekranında item çizilir.

Detay: `features/orders/presentation/providers/void_provider.dart` + `storno_log_provider.dart`.

## Test

- POS'tan 5 item gönder -> KDS ekranında 1 kitchen ticket.
- Aynı ticket'a 2 item daha ekle + send -> yeni kitchen ticket.
- KDS'de ticket'ı "ready" yap -> POS ODS ekranında görünür (eğer varsa).
- WiFi kes -> LAN sync devreye girer.
- WAN kes + LAN da kes -> POS lokal çalışmaya devam, bağlantı gelince push.

## ODS Bağlantısı

ODS (Order Display Screen) lobideki müşteriye sipariş durumunu gösterir. KDS'den gelen status değişikliklerini dinler:
- "Bon #123 hazır"
- "Bon #124 hazırlanıyor"

`apps/pos/lib/features/ods/` + `ods_app.dart`.
