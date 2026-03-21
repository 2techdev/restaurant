/// Application-wide constants for GastroCore POS.
///
/// All magic numbers and configuration defaults live here so they can be
/// referenced from a single source of truth.
library;

// ---------------------------------------------------------------------------
// Application metadata
// ---------------------------------------------------------------------------

/// Human-readable application name.
const String kAppName = 'GastroCore POS';

/// Semantic version string.
const String kAppVersion = '1.0.0';

/// Build number for store submissions.
const int kAppBuildNumber = 1;

// ---------------------------------------------------------------------------
// Currency
// ---------------------------------------------------------------------------

/// Default currency code (ISO 4217).
const String kDefaultCurrency = 'CHF';

/// All currencies the system can operate in.
const List<String> kSupportedCurrencies = ['CHF', 'EUR'];

// ---------------------------------------------------------------------------
// Tax rates (percentages)
// ---------------------------------------------------------------------------

/// Swiss VAT rates (as of 2024).
abstract final class SwissTaxRates {
  /// Standard rate for most goods and services.
  static const double standard = 8.1;

  /// Reduced rate for food, non-alcoholic beverages, books, etc.
  static const double reduced = 2.6;

  /// Special rate for accommodation services.
  static const double accommodation = 3.8;
}

/// German VAT rates.
abstract final class GermanTaxRates {
  /// Standard rate.
  static const double standard = 19.0;

  /// Reduced rate for food, books, etc.
  static const double reduced = 7.0;
}

// ---------------------------------------------------------------------------
// Sync
// ---------------------------------------------------------------------------

/// How often the device syncs with the backend (in seconds).
const int kSyncIntervalSeconds = 30;

/// Maximum retry attempts before marking sync as failed.
const int kSyncMaxRetries = 5;

/// Delay between retry attempts (in seconds).
const int kSyncRetryDelaySeconds = 10;

// ---------------------------------------------------------------------------
// Authentication & security
// ---------------------------------------------------------------------------

/// Minimum PIN length for staff login.
const int kPinLengthMin = 4;

/// Maximum PIN length for staff login.
const int kPinLengthMax = 6;

/// Number of failed PIN attempts before temporary lockout.
const int kMaxPinAttempts = 5;

/// Lockout duration after exceeding max PIN attempts (in seconds).
const int kPinLockoutSeconds = 300;

// ---------------------------------------------------------------------------
// Orders
// ---------------------------------------------------------------------------

/// Maximum number of line items allowed on a single order.
const int kMaxOrderItems = 100;

/// Maximum quantity per line item.
const int kMaxItemQuantity = 99;

// ---------------------------------------------------------------------------
// Shifts
// ---------------------------------------------------------------------------

/// Default shift duration in hours.
const int kDefaultShiftDurationHours = 8;

/// Maximum allowed shift duration in hours before a warning.
const int kMaxShiftDurationHours = 16;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Status of a restaurant table.
enum TableStatus {
  available,
  occupied,
  reserved,
  dirty,
  blocked,
}

/// Lifecycle status of an order.
enum OrderStatus {
  draft,
  open,
  sent,
  inProgress,
  ready,
  served,
  completed,
  cancelled,
  voided,
}

/// Accepted payment methods.
enum PaymentMethod {
  cash,
  card,
  twint,
  voucher,
  onAccount,
  split,
}

/// Status of a kitchen / bar ticket.
enum KitchenTicketStatus {
  pending,
  received,
  inProgress,
  ready,
  served,
  cancelled,
}
