import 'package:drift/drift.dart';

@DataClassName('SyncMetadataEntry')
class SyncMetadata extends Table {
  TextColumn get entityType => text()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  TextColumn get lastCursor => text().nullable()();

  @override
  Set<Column> get primaryKey => {entityType};
}
