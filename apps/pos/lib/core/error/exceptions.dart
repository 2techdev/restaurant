/// Typed exceptions for the data / infrastructure layer.
///
/// These are thrown at the data-source boundary and caught by repository
/// implementations, which convert them into the corresponding [Failure]
/// subclass from `failures.dart`.
library;

/// Base class for all POS exceptions.
///
/// Carries a [message] for logging and an optional machine-readable [code].
abstract class PosException implements Exception {
  const PosException({required this.message, this.code});

  /// Human-readable description suitable for logging.
  final String message;

  /// Optional error code for programmatic handling.
  final String? code;

  @override
  String toString() => '$runtimeType(message: $message, code: $code)';
}

/// Thrown when a database operation fails (insert, query, migration, etc.).
class DatabaseException extends PosException {
  const DatabaseException({
    required super.message,
    super.code,
    this.originalError,
  });

  /// The underlying error from the database driver.
  final Object? originalError;
}

/// Thrown when input validation fails before persisting or processing data.
class ValidationException extends PosException {
  const ValidationException({
    required super.message,
    super.code,
    this.field,
  });

  /// The name of the field that failed validation.
  final String? field;
}

/// Thrown when a requested entity does not exist in the data source.
class NotFoundException extends PosException {
  const NotFoundException({
    required super.message,
    super.code,
    this.entityType,
    this.entityId,
  });

  /// Type of the missing entity (e.g. 'Product').
  final String? entityType;

  /// ID of the missing entity.
  final String? entityId;
}

/// Thrown when authentication or authorisation checks fail.
class AuthException extends PosException {
  const AuthException({required super.message, super.code});
}
