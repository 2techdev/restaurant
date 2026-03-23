import 'package:drift/drift.dart';

/// Stores TSE (Technische Sicherheitseinrichtung) fiscal signatures
/// required by German KassenSichV (Kassensicherungsverordnung).
///
/// Each receipt/transaction must be signed by the TSE hardware module and
/// the resulting signature data stored for audit/tax authority inspection.
@DataClassName('FiscalSignature')
class FiscalSignatures extends Table {
  /// UUID primary key generated at signing time.
  TextColumn get id => text()();

  /// Tenant this signature belongs to.
  TextColumn get tenantId => text()();

  /// The receipt/ticket ID this signature covers.
  TextColumn get receiptId => text()();

  /// TSE device serial number (identifies the signing hardware).
  TextColumn get tseSerialNumber => text()();

  /// Monotonically increasing transaction number from the TSE.
  IntColumn get transactionNumber => integer()();

  /// TSE signature algorithm (e.g. 'ecdsa-plain-SHA384').
  TextColumn get signatureAlgorithm => text()();

  /// Base64-encoded TSE signature value.
  TextColumn get signatureValue => text()();

  /// TSE process type string (e.g. 'Kassenbeleg-V1').
  TextColumn get processType => text()();

  /// Signed process data (JSON or plain text as defined by DSFinV-K).
  TextColumn get processData => text()();

  /// UTC timestamp from the TSE at time of signing.
  DateTimeColumn get tseTimestamp => dateTime()();

  /// UTC timestamp when this record was created locally.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
