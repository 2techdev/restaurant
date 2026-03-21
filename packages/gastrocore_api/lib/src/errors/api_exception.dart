/// Typed exception thrown by all API client methods on non-2xx responses.
library;

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? errorCode;

  const ApiException({
    required this.statusCode,
    required this.message,
    this.errorCode,
  });

  /// True for 401 / 403 responses.
  bool get isAuthError =>
      statusCode == 401 || statusCode == 403;

  /// True for 404 Not Found responses.
  bool get isNotFound => statusCode == 404;

  /// True for 5xx server errors.
  bool get isServerError => statusCode >= 500;

  /// True for 4xx client errors (excluding auth errors).
  bool get isClientError =>
      statusCode >= 400 && statusCode < 500 && !isAuthError;

  @override
  String toString() =>
      'ApiException(status: $statusCode, message: $message'
      '${errorCode != null ? ", code: $errorCode" : ""})';
}
