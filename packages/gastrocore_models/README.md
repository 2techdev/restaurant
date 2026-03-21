# gastrocore_models

Pure-Dart domain models shared across all GastroCore apps (POS, Waiter, Kiosk, KDS, ODS, Online Ordering, Dashboard).

## Contents

- **Entities** — Immutable domain objects: `TicketEntity`, `OrderItemEntity`, `ProductEntity`, `CategoryEntity`, `ModifierEntity`, `UserEntity`, `ShiftEntity`, `PaymentEntity`, `RestaurantTableEntity`, `SyncEventEntity`
- **Enums** — `OrderType`, `TicketStatus`, `OrderChannel`, `DiscountType`, `PaymentMethod`, `UserRole`, `ShiftStatus`, `TableStatus`, ...
- **Fare Engine** — `FareEngine` (pure calculation, no DB deps) + `FareConfig`, `FareBreakdown`, `FareLineItem` and all related models
- **Utils** — `Money` value object (integer cents, Swiss rounding, tax helpers)

## Usage

```dart
import 'package:gastrocore_models/gastrocore_models.dart';

final price = Money(1500); // CHF 15.00
print(price.format('CHF')); // "CHF 15.00"

final ticket = TicketEntity(
  id: 'ticket-1',
  tenantId: 'tenant-1',
  orderNumber: '0042',
  orderType: OrderType.dineIn,
  openedAt: DateTime.now(),
  deviceId: 'pos-1',
);
```

## Design Principles

- **No Flutter dependency** — all models are pure Dart, usable in CLI, server, and any Flutter app
- **Integer pricing** — all monetary values stored as cents (int) to avoid floating-point rounding
- **Immutable with copyWith** — all entities are `const`-constructible and provide `copyWith`
- **JSON serialization** — all entities have `fromJson` / `toJson` for API interop
