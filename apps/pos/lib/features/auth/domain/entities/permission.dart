/// Role-based permission gates for the POS terminal.
///
/// Turkish role semantics:
///   Kasiyer   → [UserRole.cashier]  (order + pay + print + call waiter)
///   Şef       → [UserRole.manager]  (kasiyer + storno + discount)
///   Yönetici  → [UserRole.admin]    (şef + Z-Report + settings + happy hour)
///
/// The existing [UserRole] enum lives in [user_entity.dart]; rather than
/// introduce a parallel enum we map the Turkish business roles onto the
/// canonical English ones. [waiter] and [kitchen] are treated as kasiyer-level
/// for the purposes of these gates (they can place orders but cannot void or
/// discount without manager approval).
library;

import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';

// ---------------------------------------------------------------------------
// Permission enum
// ---------------------------------------------------------------------------

/// A single capability the UI may gate on. Grouped by business area.
enum Permission {
  // Kasiyer (cashier) tier ----------------------------------------------------
  /// Create / edit open orders.
  order,

  /// Take payment and close the ticket.
  pay,

  /// Print receipts / bills / kitchen tickets.
  print,

  /// Call a waiter (çağır garson bell).
  callWaiter,

  // Şef (manager) tier --------------------------------------------------------
  /// Void a ticket or line (İPTAL / Storno).
  storno,

  /// Apply a discount / Rabatt / indirim.
  discount,

  // Yönetici (admin) tier -----------------------------------------------------
  /// Generate / print the Z-Bericht (daily Z-report).
  zReport,

  /// Open the Settings screen.
  settings,

  /// Configure happy-hour pricing rules.
  happyHourConfig,
}

// ---------------------------------------------------------------------------
// Role → permission map
// ---------------------------------------------------------------------------

/// Base permissions granted to a cashier / kasiyer.
const Set<Permission> _kKasiyerPerms = {
  Permission.order,
  Permission.pay,
  Permission.print,
  Permission.callWaiter,
};

/// Şef inherits kasiyer permissions plus storno + discount.
const Set<Permission> _kSefPerms = {
  ..._kKasiyerPerms,
  Permission.storno,
  Permission.discount,
};

/// Yönetici inherits şef permissions plus reporting + settings.
const Set<Permission> _kYoneticiPerms = {
  ..._kSefPerms,
  Permission.zReport,
  Permission.settings,
  Permission.happyHourConfig,
};

/// Static lookup table keyed by the canonical [UserRole].
///
/// Turkish mapping:
///   cashier/waiter/kitchen → kasiyer
///   manager                → şef
///   admin                  → yönetici
const Map<UserRole, Set<Permission>> kRolePermissions = {
  UserRole.admin: _kYoneticiPerms,
  UserRole.manager: _kSefPerms,
  UserRole.cashier: _kKasiyerPerms,
  UserRole.waiter: _kKasiyerPerms,
  UserRole.kitchen: _kKasiyerPerms,
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns true when [role] is allowed to perform [p].
bool roleCan(UserRole role, Permission p) {
  final perms = kRolePermissions[role];
  return perms != null && perms.contains(p);
}

/// Standard tooltip string shown on gated, disabled controls.
///
/// Kept in Turkish to match the pilot UI copy in [ActionRail] and the order
/// screens.
const String kPermissionRequiredTooltip = 'Yetki gerekli';
