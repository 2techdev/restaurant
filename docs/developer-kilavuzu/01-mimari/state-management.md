# State Management (Riverpod)

POS, `flutter_riverpod ^2.6.1` kullanır. Provider-based reactive state.

## Provider Türleri

### StateProvider
En basit tür. Değeri değiştirilebilen tek bir değer.

**Örnek**: `pos_v2_shell.dart:44-59` içindeki UI provider'ları.
```dart
final v2SelectedLineIdProvider = StateProvider<String?>((ref) => null);
final v2RailActiveProvider = StateProvider<String>((ref) => 'sale');
final productImagesEnabledProvider = StateProvider<bool>((ref) => false);

enum PosPalette { ivory, midnight }
final posPaletteProvider = StateProvider<PosPalette>((ref) => PosPalette.ivory);
```

Okuma: `ref.watch(v2RailActiveProvider)`. Yazma: `ref.read(v2RailActiveProvider.notifier).state = 'settings'`.

### StateNotifierProvider
Karmaşık iş mantığı için. `StateNotifier<T>` sınıfı iç state'i kontrol eder.

**Örnek**: `features/orders/presentation/providers/order_provider.dart` içindeki `currentTicketProvider`.

```dart
final currentTicketProvider = StateNotifierProvider<CurrentTicketNotifier, TicketEntity?>(
  (ref) => CurrentTicketNotifier(ref),
);
```

`CurrentTicketNotifier` şunları yönetir:
- `addItem(product, quantity)` - sepete ürün ekle
- `removeItem(itemId)` - ürün çıkar
- `sendToKitchen()` - gönderilmemiş kalemleri mutfağa bildir
- `createNewTicket(...)` - yeni sepet aç
- `applyOverride(action)` - cashier override uygula

UI tarafi:
```dart
final ticket = ref.watch(currentTicketProvider);
ref.read(currentTicketProvider.notifier).addItem(product);
```

### FutureProvider
Async yükleme. `AsyncValue<T>` döner.

**Örnek**: Menu yüklemesi.
```dart
final productsProvider = FutureProvider<List<ProductEntity>>((ref) async {
  final repo = ref.watch(menuRepositoryProvider);
  return repo.listProducts();
});
```

UI tarafı:
```dart
final productsAsync = ref.watch(productsProvider);
productsAsync.when(
  data: (products) => _ItemsGrid(products: products, ...),
  loading: () => const CircularProgressIndicator(),
  error: (err, _) => Text('Menü yüklenemedi: $err'),
);
```

Bu pattern POS v2 shell'inde `_ItemsWrap.build` (pos_v2_shell.dart:~1844) içinde direkt görülebilir.

### Provider (Readonly)
Derived / hesaplanmış değerler için. Set edilemez.

```dart
final currentUserProvider = Provider<UserEntity?>((ref) {
  return ref.watch(authProvider).user;
});
```

### Family
Parametre alan provider'lar. Rezervasyonda bir tarihe göre filtre gibi.

```dart
final reservationsByDateProvider = FutureProvider.family<List<ReservationEntity>, DateTime>((ref, date) async {
  return ref.watch(reservationRepoProvider).forDate(date);
});
```

Kullanım: `ref.watch(reservationsByDateProvider(DateTime.now()))`.

### AutoDispose
Ekran açıldığında yaratılsın, kapandığında otomatik dispose edilsin. `productsProvider.autoDispose`.

POS'da çoğunlukla kasiyerin uzun oturumu olduğu için `autoDispose` az kullanılır. Uzun yaşayan state (mevcut ticket, current user) tercih edilir.

## Ref Nesnesi ve Kural Farklılığı

| Metot | Ne yapar | Ne zaman |
|---|---|---|
| `ref.watch(p)` | Okur + değişimi dinler, rebuild tetikler | `build()` içinde |
| `ref.read(p)` | Tek seferlik okur | Callback / onTap |
| `ref.listen(p, cb)` | Dinler ama rebuild etmez, callback çağırır | Navigation, SnackBar |
| `ref.invalidate(p)` | Provider'ı resetle, yeniden yükle | Pull-to-refresh |
| `ref.read(p.notifier)` | Notifier'a eriş (metot çağrısı için) | onTap callback'leri |

**Kritik hata**: `onTap: () { ref.watch(...) }` yazmak. Callback içinde `watch` olmaz, `read` olur.

## ConsumerWidget + ConsumerStatefulWidget

```dart
class FineDiningShell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(body: PosV2Shell());
  }
}
```

`ref`'e `build(context, ref)` üzerinden ulaşılır. `StatefulWidget` versiyonu `ConsumerStatefulWidget` + `ConsumerState`.

## Provider Yerleşimi

| Nereye | Ne konur |
|---|---|
| `core/providers/` | Global (currentUser, connectivity, sync status) |
| `core/di/providers.dart` | Repository / service injection |
| `features/<f>/presentation/providers/` | Sadece UI state |
| `features/<f>/data/` | Repository provider (bazı yerlerde `di/`'a da konabilir) |

`di/providers.dart` altında tipik:
```dart
final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepositoryImpl(
    local: ref.watch(orderLocalDataSourceProvider),
    remote: ref.watch(orderRemoteDataSourceProvider),
  );
});
```

## Root ProviderScope

`apps/pos/lib/main.dart` içinde uygulamanın en tepesi:
```dart
runApp(
  ProviderScope(
    overrides: [...],
    child: const PosApp(),
  ),
);
```

Test ortaminda `overrides` ile provider'lar mock ile değiştirilebilir.

## Pratik Pattern'ler

### A) "Ana POS Shell" pattern
`pos_v2_shell.dart` birkaç `StateProvider` ile UI state tutar (selected line id, palette, rail active). Bu state'ler hafif ve ekrana özeldir.

### B) "Current Ticket" pattern
`currentTicketProvider` tüm POS oturumu boyunca canlıdır. Ödeme tamamlanınca reset edilir, sepet yeni bir UUID'ye döner.

### C) "AsyncValue.when" pattern
Veri çeken her ekran `FutureProvider` + `.when(data, loading, error)` kullanır. Loading / error UI'da kaybolmaz.

### D) "Invalidate on write" pattern
Yeni bir ürün eklendiğinde `ref.invalidate(productsProvider)` ile liste yeniden yüklenir. Manuel senkronizasyon gerekmez.

## Kod Üretimi (Opsiyonel)

`riverpod_generator ^2.6.3` kullanan dosyalar:
```dart
@riverpod
class OrderNotifier extends _$OrderNotifier {
  @override
  TicketEntity? build() => null;
  void addItem(...) {}
}
```

`dart run build_runner build` sonrası `.g.dart` dosyası oluşur. POS şu an her yerde kullanmıyor, mixin pattern da geçerli. Yeni kod yazarken generator tercih edilebilir.
