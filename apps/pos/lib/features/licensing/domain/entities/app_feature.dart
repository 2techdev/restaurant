/// Enumeration of every feature that can be gated behind a license tier.
///
/// Each value declares the minimum [LicenseTier] required to use that feature.
/// The [FeatureFlagService] consults these requirements when evaluating access.
library;

import 'license_tier.dart';

enum AppFeature {
  // -------------------------------------------------------------------------
  // FREE tier — always available
  // -------------------------------------------------------------------------

  /// Core order-taking and payment processing.
  basicPos(LicenseTier.free, 'Basic POS'),

  /// Single-device operation (one register per installation).
  singleDevice(LicenseTier.free, 'Single Device'),

  /// Menu limited to 50 active items.
  limitedMenu(LicenseTier.free, 'Menu (up to 50 items)'),

  /// End-of-day summary and shift totals.
  basicReports(LicenseTier.free, 'Basic Reports'),

  // -------------------------------------------------------------------------
  // STARTER tier
  // -------------------------------------------------------------------------

  /// Detailed analytics: revenue breakdown, category performance, trends.
  advancedReports(LicenseTier.starter, 'Advanced Reports'),

  /// Receipt printing support (thermal / PDF / email).
  printing(LicenseTier.starter, 'Receipt Printing'),

  // -------------------------------------------------------------------------
  // PROFESSIONAL tier
  // -------------------------------------------------------------------------

  /// Unlimited product count in the menu.
  unlimitedMenu(LicenseTier.professional, 'Unlimited Menu Items'),

  /// Kitchen Display System — real-time ticket view for kitchen staff.
  kds(LicenseTier.professional, 'Kitchen Display System (KDS)'),

  /// Inventory tracking and stock management.
  inventory(LicenseTier.professional, 'Inventory Management'),

  /// CRM loyalty program and customer profiles.
  crm(LicenseTier.professional, 'CRM & Loyalty'),

  /// Fully customisable receipt header, footer, and logo.
  customReceipts(LicenseTier.professional, 'Custom Receipts'),

  /// SQLite database export and import for disaster recovery.
  backupRestore(LicenseTier.professional, 'Backup & Restore'),

  // -------------------------------------------------------------------------
  // ENTERPRISE tier
  // -------------------------------------------------------------------------

  /// Bidirectional sync with the GastroCore cloud backend.
  cloudSync(LicenseTier.enterprise, 'Cloud Sync'),

  /// Multiple POS registers connected over the network.
  multiDevice(LicenseTier.enterprise, 'Multi-Device Sync'),

  /// REST API access for third-party integrations.
  apiAccess(LicenseTier.enterprise, 'API Access'),

  /// Manage multiple restaurant locations from a single account.
  multiLocation(LicenseTier.enterprise, 'Multi-Location'),

  /// Webhooks, custom payment terminals, and bespoke integrations.
  customIntegrations(LicenseTier.enterprise, 'Custom Integrations');

  const AppFeature(this.requiredTier, this.displayName);

  /// Minimum tier needed to enable this feature.
  final LicenseTier requiredTier;

  /// Human-readable name for upgrade prompts and settings UI.
  final String displayName;
}
