import 'package:drift/drift.dart';

@DataClassName('SyncQueueEntry')
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()(); // create, update, delete
  TextColumn get payloadJson => text()();
  TextColumn get deviceId => text()();
  DateTimeColumn get timestamp => dateTime()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, uploading, uploaded, failed
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}
