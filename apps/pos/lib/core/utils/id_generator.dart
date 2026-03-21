/// UUID and identifier generation utilities for the POS system.
///
/// All entity IDs use UUID v4 for global uniqueness across devices.
/// Order numbers use a human-readable daily sequence format.
library;

import 'package:uuid/uuid.dart';

/// Singleton UUID generator instance.
const _uuid = Uuid();

/// Generates identifiers for entities, orders, and devices.
abstract final class IdGenerator {
  /// Generate a new UUID v4 string for entity identification.
  ///
  /// Example: "f47ac10b-58cc-4372-a567-0e02b2c3d479"
  static String generateId() => _uuid.v4();

  /// Generate a human-readable order number from a daily sequence counter.
  ///
  /// Format: zero-padded 4-digit string.
  /// - `generateOrderNumber(1)`  -> "0001"
  /// - `generateOrderNumber(42)` -> "0042"
  ///
  /// The [dailySequence] resets to 1 at the start of each business day.
  static String generateOrderNumber(int dailySequence) {
    assert(dailySequence > 0, 'Daily sequence must be positive');
    return dailySequence.toString().padLeft(4, '0');
  }

  /// Generate a unique device identifier.
  ///
  /// Prefixed with "DEV-" for easy identification in logs and sync payloads.
  /// Example: "DEV-f47ac10b-58cc-4372-a567-0e02b2c3d479"
  static String generateDeviceId() => 'DEV-${_uuid.v4()}';

  /// Generate a unique receipt number combining date and sequence.
  ///
  /// Format: "YYYYMMDD-NNNN"
  /// Example: "20260320-0001"
  static String generateReceiptNumber(DateTime date, int dailySequence) {
    final datePart =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final seqPart = dailySequence.toString().padLeft(4, '0');
    return '$datePart-$seqPart';
  }
}
