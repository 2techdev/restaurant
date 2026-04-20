# Testleri Çalıştır

POS'ta üç tür test: unit, widget, integration.

## Unit Tests

**Dizin**: `apps/pos/test/`

Domain + data katmanı için. Flutter bağımlılığı olmayan saf Dart testleri hızlı çalışır.

### Çalıştırma
```bash
cd apps/pos
flutter test                          # tüm testler
flutter test test/core/                # sadece core testleri
flutter test test/features/orders/     # sadece orders feature
flutter test --name "fare_engine"      # isim filtresi
```

### Örnek Test

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/services/fare_engine.dart';

void main() {
  group('FareEngine', () {
    test('dine-in food uses 8.1% rate', () {
      final result = FareEngine().calculate(
        config: _testConfig,
        orderType: OrderType.dineIn,
        lines: [CartLine(taxRateCode: 'food', brutto: 1000)],
      );
      expect(result.taxBreakdown['8.1'], equals(75));
    });
  });
}
```

### Mocking

`mockito` veya `mocktail` kullanılır. Genellikle `mocktail` tercih (null-safety dostu):
```dart
class MockOrderRepository extends Mock implements OrderRepository {}

test('creates ticket', () {
  final repo = MockOrderRepository();
  when(() => repo.save(any())).thenAnswer((_) async {});
  // ...
});
```

### Drift In-Memory

DB test'leri için:
```dart
import 'package:drift/native.dart';

final db = AppDatabase(NativeDatabase.memory());
addTearDown(db.close);
await db.into(db.products).insert(ProductsCompanion.insert(...));
```

Her test kendi in-memory DB'si ile başlar, tear-down'da kapatılır.

## Widget Tests

**Dizin**: `apps/pos/test/` (widget klasörlerinde)

UI widget'larının izolasyon testleri. `WidgetTester` ile pump + interact.

### Örnek

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('BEZAHLEN disabled when empty ticket', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentTicketProvider.overrideWith((ref) => null),
        ],
        child: const MaterialApp(home: Scaffold(body: BottomActionBar())),
      ),
    );

    final payBtn = find.text('BEZAHLEN');
    expect(payBtn, findsOneWidget);
    await tester.tap(payBtn);
    await tester.pump();
    // beklenen: hiçbir navigation tetiklenmedi
  });
}
```

### Golden Tests (Screenshot)

Görsel regresyon için:
```bash
flutter test --update-goldens                  # baseline üret
flutter test                                    # karşılaştır
```

`test/goldens/` altında `.png` dosyalari. Git'e commit edilir. CI'da diff çıkarsa test fail.

## Integration Tests

**Dizin**: `apps/pos/integration_test/`

End-to-end, gerçek cihaz / emulator üstünde. `integration_test: sdk: flutter` dev dep.

### Çalıştırma
```bash
flutter test integration_test/app_test.dart
```

### Örnek

```dart
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full payment flow', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // login ekranı
    await tester.enterText(find.byKey(const Key('pin')), '1234');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    // sepete ürün ekle
    await tester.tap(find.text('Pizza Margherita'));
    await tester.pumpAndSettle();

    // BEZAHLEN
    await tester.tap(find.text('BEZAHLEN'));
    await tester.pumpAndSettle();
    // ...
  });
}
```

Integration testleri yavaş, CI'da selective çalıştırılır.

## Test Coverage

```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

Çıktı: `coverage/html/index.html` tarayıcıda açılır.

Hedef: domain %90+, data %80+, presentation %50+ (UI test pahalı).

## CI Entegrasyonu

`.github/workflows/` altında (tipik):
```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.35.0'
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test --coverage
      - uses: codecov/codecov-action@v4
```

POS için gerçek CI tanımi root'ta `.github/workflows/` klasöründe.

## Backend Go Tests

Bu kılavuzun kapsamı dışı ama:
```bash
cd server
go test ./...
```

## Tipik Test Hiyerarşisi

| Katman | Test türü | Örnek |
|---|---|---|
| `domain/entities/` | Unit | Entity equality, toJson |
| `domain/services/` | Unit | FareEngine, SeatSplitCalculator |
| `data/repositories/` | Unit + mocks | RepositoryImpl behavior |
| `data/daos/` | Drift in-memory | DAO query correctness |
| `presentation/providers/` | Provider test | StateNotifier state transitions |
| `presentation/widgets/` | Widget | Render + tap interactions |
| `presentation/screens/` | Widget | Screen-level flow |
| Full app | Integration | E2E user journey |

## Flaky Test'lerden Kaçınma

- `Future.delayed` asla kullanma. `tester.pump(Duration(...))` ile simulated time.
- Network gerçek değil mock. `http_mock_adapter` veya `mocktail`.
- `DateTime.now()` yerine `Clock` abstraction.
- Provider override ile deterministic state.

## Sık Kullanılan Paketler

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  mocktail: ^1.0.0
  http_mock_adapter: ...
```

`mocktail` null-safety ile daha iyi çalışır, `mockito`'ya tercih.

## Testleri Unuttuğun Yerler

- Drift migration'ları (schema bump sonrası onUpgrade test et).
- Swiss rounding (`roundToFiveRappen` cases: 0.00, 0.02, 0.03, 0.07, 0.99).
- Happy hour + takeaway kombinasyonu (hangi rate, hangi indirim).
- Void + refund audit log entry (her ikisi de log atar mı?).
- Offline mode (SyncQueue kayıtları doğru tiyatro mu?).

## Flaky Network Gerçek Test

Gerçek integration test'i Wallee sandbox'a kadar gider. Bu testler `@tags(['network'])` ile işaretlenir ve sadece merkezi CI'da çalışır, dev lokalde atlanır:
```bash
flutter test --exclude-tags network
```
