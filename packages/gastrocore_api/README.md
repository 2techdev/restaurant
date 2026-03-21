# gastrocore_api

HTTP API client for the GastroCore Go backend. Provides typed methods for every endpoint, request/response DTOs, and consistent error handling.

## Usage

```dart
import 'package:gastrocore_api/gastrocore_api.dart';

final client = GastrocoreClient(baseUrl: 'https://api.example.com');

// Auth
final token = await client.auth.login(tenantId: 't1', pin: '1234');

// Menu
final menu = await client.menu.getMenu(tenantId: 't1');

// Orders
final tickets = await client.orders.getOpenTickets(tenantId: 't1');
final ticket  = await client.orders.createTicket(tenantId: 't1', ticket: newTicket);

// Tables
final tables = await client.tables.getTables(tenantId: 't1');

// Sync
await client.sync.pushEvents(tenantId: 't1', events: outboxEvents);
final pull  = await client.sync.pullChanges(tenantId: 't1', cursor: lastCursor);
```

## Error handling

All methods throw `ApiException` on HTTP errors.

```dart
try {
  await client.menu.getMenu(tenantId: 't1');
} on ApiException catch (e) {
  print('HTTP ${e.statusCode}: ${e.message}');
}
```
