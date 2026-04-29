# Bottom Action Bar

POS v2 shell'inin alt kısmında sabit duran 3 küme (left - total - right) footer.

**Dosya**: [apps/pos/lib/features/orders/presentation/widgets/shell/bottom_action_bar.dart](../../../apps/pos/lib/features/orders/presentation/widgets/shell/bottom_action_bar.dart)

## Düzen

```
┌────────────────────────────────────────────────────────────────────────────┐
│ [SCHLIESSEN] [NEUER BON] [SENDEN]    GESAMT  CHF 42.50    [TEILEN] [KARTE] [BEZAHLEN] │
└────────────────────────────────────────────────────────────────────────────┘
```

Sol küme - Orta readout (Expanded) - Sağ küme.

## Yükseklik

```dart
height: AppTokens.bottomBarHeight + 8     // 64 + 8 = 72
```

Padding `EdgeInsets.symmetric(horizontal: 8, vertical: 8)`.

Arka plan `GcColors.surfaceContainerHigh` (`0xFFDEE3E6`).

## Sol Küme

### `_CloseButton` (bottom_action_bar.dart:166)
SCHLIESSEN - sales shell'i kapatır.

```dart
onTap: () {
  if (Navigator.canPop(context)) {
    Navigator.pop(context);
  } else {
    context.go(AppRoutes.home);
  }
},
```

- Genişlik sabit 130px, yükseklik `touchLarge` (56).
- Arka plan `GcColors.catRed`.
- İkon `Icons.close_rounded` + "SCHLIESSEN" yazısı.
- Üst kenar `kInsetHighlight` (2px beyaz inset line).

### NEUER BON (`_SecondaryButton`)
Mevcut ticket'ı parkla, yeni bir ticket aç.

```dart
Future<void> _onNewTicket(BuildContext context, WidgetRef ref, {required bool hasItems}) async {
  if (hasItems) {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neuen Bon starten?'),
        content: const Text(
          'Der aktuelle Bon hat noch Artikel. Beim Start eines '
          'neuen Bons gehen nicht gesendete Änderungen verloren.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Neu starten')),
        ],
      ),
    );
    if (confirm != true) return;
  }
  final user = ref.read(currentUserProvider);
  await ref.read(currentTicketProvider.notifier).createNewTicket(
    deviceId: 'DEV-POS-01',
    waiterId: user?.id,
  );
}
```

- Mevcut ticket'ta item varsa confirm dialog.
- Onay sonrası `createNewTicket` çağrılır.
- `deviceId: 'DEV-POS-01'` hardcoded - device registry olduğunda parameterize edilmeli.

### SENDEN (`_SecondaryButton`)
Gönderilmemiş kalemleri mutfağa bildir.

```dart
Future<void> _onSend(BuildContext context, WidgetRef ref) async {
  await ref.read(currentTicketProvider.notifier).sendToKitchen();
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('An die Küche gesendet'),
      duration: Duration(seconds: 2),
    ),
  );
}
```

- `enabled: hasUnsent` -> hiç `sentToKitchen == false` kalem yoksa disabled.
- `sendToKitchen` içinde `KitchenTicket` yaratılır, item'lar `sentToKitchen = true` işaretlenir.
- KDS bu kitchen_ticket'ları WebSocket ile alır (cloud üzerinden veya LAN).

## Orta Küme: `_TotalReadout`

`GESAMT` yazısı + büyük fiyat.

```dart
Container(
  height: AppTokens.touchLarge,
  decoration: const BoxDecoration(color: GcColors.surfaceContainerLowest),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text('GESAMT', style: GcText.labelTiny),
      const SizedBox(width: 12),
      Text(
        'CHF $whole.$frac',
        style: GcText.displayBlack.copyWith(
          fontSize: 24,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  ),
)
```

- Tabular figures sayesinde rakamlar aynı genişlikte (kasiyer gözü kaymaz).
- Work Sans Black (w900) ağırlık.
- `whole = totalCents ~/ 100`, `frac = (totalCents % 100).toString().padLeft(2, '0')`.

## Sağ Küme

### TEILEN (`_SecondaryButton`)
Split bill dialogu.

```dart
onTap: () {
  if (ticket == null) return;
  context.push(AppRoutes.splitBillFor(ticket.id));
},
```

`AppRoutes.splitBillFor(ticketId)` -> `/tickets/:id/split` route'u.

### KARTE (`_SecondaryButton`)
Doğrudan kart ödeme akışına sıçrama.

```dart
onTap: () => _openPayment(context, ticket),
```

Genel `_openPayment` içinde `OrderPaymentScreen`'e yönlendirir, kart ön-seçili olarak.

### BEZAHLEN (`_PayButton`) - Ana CTA

```dart
class _PayButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? GcColors.catGreen : GcColors.surfaceContainerHighest,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          height: AppTokens.touchLarge,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: enabled ? kCashGradient : null,
            border: enabled ? const Border(top: BorderSide(color: kInsetHighlight, width: 2)) : null,
          ),
          child: Row(
            children: [
              Icon(Icons.payments_rounded, size: 20, color: enabled ? Colors.white : GcColors.outlineVariant),
              const SizedBox(width: 8),
              Text('BEZAHLEN', style: TextStyle(
                fontFamily: 'WorkSans',
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: enabled ? Colors.white : GcColors.outlineVariant,
                letterSpacing: 0.8,
              )),
            ],
          ),
        ),
      ),
    );
  }
}
```

- `kCashGradient` yeşil 2-stop gradient.
- `kInsetHighlight` üst inset highlight (neomorphic buton hissi).
- Disabled durumda gradient yok, `surfaceContainerHighest` düz renk.

### _openPayment (bottom_action_bar.dart:151)

```dart
void _openPayment(BuildContext context, TicketEntity? ticket) {
  if (ticket == null) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => OrderPaymentScreen(ticketId: ticket.id),
      fullscreenDialog: true,
    ),
  );
}
```

`fullscreenDialog: true` -> dikey sheet animasyonuyla açılır. Android'de back button ödeme ekranından çıkar.

## Enabled / Disabled Mantığı

```dart
final ticket     = ref.watch(currentTicketProvider);
final hasTicket  = ticket != null;
final hasItems   = hasTicket && ticket.items.isNotEmpty;
final hasUnsent  = hasItems && ticket.items.any((i) => !i.sentToKitchen);
final total      = ticket?.total ?? 0;
```

| Buton | Enable koşulu |
|---|---|
| SCHLIESSEN | her zaman |
| NEUER BON | her zaman |
| SENDEN | `hasUnsent` |
| TEILEN | `hasItems` |
| KARTE | `hasItems` |
| BEZAHLEN | `hasItems` |

Disable olduğunda buton gri (`GcColors.surfaceContainerHighest`), ikon ve yazı `GcColors.outline`. Bar layout değişmez.

## Bar Reflow Yok

Bar ne ticket durumuna ne de farklı total uzunluğuna göre genişlik değiştirir. Buton genişlikleri sabit veya `minWidth: 96`. Total readout `Expanded` ile kalan alanı alır - böylece sağ küme de konumunu sabit tutar.

## Tipografi

- Buton label'ları: Work Sans ExtraBold (w800), 12px, letterSpacing 0.6.
- BEZAHLEN: Work Sans Black (w900), 14px, letterSpacing 0.8.
- GESAMT label: `GcText.labelTiny` (Work Sans ExtraBold, 10-11px).
- Total rakam: Work Sans Black, 24px, tabular figures.

## Test

- Empty ticket -> sadece SCHLIESSEN ve NEUER BON enabled.
- 1 item ekle -> BEZAHLEN, KARTE, TEILEN enabled, SENDEN enabled.
- SENDEN'e bas -> items `sentToKitchen = true`, SENDEN disable olur.
- NEUER BON + item var -> confirm dialog.
- BEZAHLEN -> `OrderPaymentScreen`.
