/// Domain-level failure types for functional error handling.
///
/// Use [Failure] subclasses instead of throwing exceptions in the domain and
/// data layers. Pair with `Either<Failure, T>` (from dartz/fpdart) or a
/// sealed Result type so callers handle errors explicitly.
library;

/// Base class for all domain failures.
///
/// Every failure carries a human-readable [message] and an optional
/// machine-readable [code] for programmatic branching.
abstract class Failure {
  const Failure({required this.message, this.code});

  /// Human-readable error description (may be shown in UI or logs).
  final String message;

  /// Optional error code for programmatic handling.
  final String? code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          code == other.code;

  @override
  int get hashCode => Object.hash(runtimeType, message, code);

  @override
  String toString() => '$runtimeType(message: $message, code: $code)';
}

/// Failure originating from the local database (Drift / SQLite).
class DatabaseFailure extends Failure {
  const DatabaseFailure({
    required super.message,
    super.code,
    this.originalError,
  });

  /// The underlying database error, if available.
  final Object? originalError;
}

/// Input validation failure (e.g. invalid PIN, empty required field).
class ValidationFailure extends Failure {
  const ValidationFailure({
    required super.message,
    super.code,
    this.field,
  });

  /// The name of the field that failed validation, if applicable.
  final String? field;
}

/// Requested entity was not found.
class NotFoundFailure extends Failure {
  const NotFoundFailure({
    required super.message,
    super.code,
    this.entityType,
    this.entityId,
  });

  /// Type of the missing entity (e.g. 'Order', 'Product').
  final String? entityType;

  /// ID of the missing entity.
  final String? entityId;
}

/// Authentication or authorisation failure (wrong PIN, insufficient role).
class AuthFailure extends Failure {
  const AuthFailure({required super.message, super.code});
}

/// Cloud synchronisation failure.
class SyncFailure extends Failure {
  const SyncFailure({
    required super.message,
    super.code,
    this.statusCode,
  });

  /// HTTP status code returned by the sync endpoint, if applicable.
  final int? statusCode;
}

/// Printer communication failure (receipt / kitchen printer).
class PrinterFailure extends Failure {
  const PrinterFailure({
    required super.message,
    super.code,
    this.printerName,
  });

  /// Name or address of the printer that failed.
  final String? printerName;
}
