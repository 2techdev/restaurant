# gastrocore_printers

ESC/POS printer integration for GastroCore POS.

## Scope

Three target printers per store:

- **kitchen** — mutfak backup ticket (KDS asıl)
- **bar** — bar ticket
- **receipt** — cashier fişi (ödeme sonrası)

Protocol: ESC/POS (Epson). Transport: TCP/IP (ethernet). USB is future work.

## Structure

```
lib/
  gastrocore_printers.dart           # public barrel
  src/
    models/
      printer_config.dart            # IP, port, target, enabled, backup
      printer_target.dart            # kitchen / bar / receipt enum
      printer_status.dart            # online/offline/error + last-seen
      receipt_data.dart              # print-ready receipt DTO
      kitchen_ticket_data.dart       # print-ready kitchen/bar DTO
    service/
      printer_service.dart           # abstract interface
      esc_pos_printer_service.dart   # real TCP/IP impl
      mock_printer_service.dart      # in-memory buffer for tests
    templates/
      receipt_template.dart          # 80mm receipt w/ Swiss MWST + QR
      kitchen_ticket_template.dart   # gang-grouped, big-qty, allergy
      common.dart                    # shared formatting helpers
```

## Usage (consumer — POS / KDS / Waiter apps)

```dart
final service = EscPosPrinterService(configs: await loadFromBackend());

// Send kitchen ticket on order fire
await service.printOrderTicket(ticket, target: PrinterTarget.kitchen);

// Print receipt on payment complete
await service.printReceipt(receipt);

// Backoffice test print
final ok = await service.testPrint(config);
```

## Swiss MWST

- Dine-in: 8.1%
- Takeaway: 2.6%
- Derived from `TicketEntity.orderType`, not hard-coded per store.

## Package choice

- `esc_pos_utils_plus: ^2.0.4` — generator (pure Dart, cross-platform).
- `esc_pos_printer_plus: ^0.1.1` — NetworkPrinter transport (TCP/IP).

`_plus` forks chosen because upstream `esc_pos_printer`/`esc_pos_utils` are
abandoned since 2021 (null-safety branch stale). The `_plus` variants are
used by several active POS apps and stay current with Dart SDK.

## What this package is NOT

- Not a UI package — no buttons, dialogs, or screens. Consumer apps build
  their own print buttons and call into `PrinterService`.
- Not a device-discovery library — consumers configure static IPs via
  backoffice. Zero-conf/mDNS is future work.
