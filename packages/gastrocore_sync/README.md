# gastrocore_sync

Offline-first sync engine for GastroCore apps.

## Architecture

### Cloud Sync (Outbox Pattern)
Changes made offline are queued in an outbox. When connectivity is restored, `OutboxService` pushes them to the Go backend in order.

### Cursor-based Pull
`CursorPullService` fetches changes from the server using an opaque cursor, enabling efficient incremental sync.

### LAN Sync
`LanSyncService` discovers other GastroCore devices on the local network (via mDNS/UDP broadcast) and syncs directly without a cloud round-trip — useful for kitchen displays and waiter apps on the same Wi-Fi.

### Conflict Resolution
`ConflictResolver` applies deterministic last-write-wins by `updatedAt` timestamp, with optional merge hooks for entities that need custom merging (e.g. tickets with concurrent item additions).

## Usage

```dart
import 'package:gastrocore_sync/gastrocore_sync.dart';

// Push pending outbox events
final outbox = OutboxService(repository: myOutboxRepo, apiClient: client);
await outbox.flush();

// Pull latest changes from server
final puller = CursorPullService(apiClient: client, store: myLocalStore);
await puller.pull(tenantId: 't1');

// Resolve conflicts
final resolver = ConflictResolver();
final resolved = resolver.resolve(localRecord, remoteRecord);
```
