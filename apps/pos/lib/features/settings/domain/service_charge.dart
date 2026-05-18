/// Shared service-charge derivation.
///
/// The service-charge feature is configured in [RestaurantSettings]
/// ([serviceChargeEnabled] + [serviceChargePercent]) but the actual
/// cents amount has to be computed from the running subtotal every
/// time the cart UI repaints. We avoid mutating
/// [TicketEntity.serviceFeeAmount] on every keystroke and instead
/// derive the value on read — the receipt screen, the totals footer,
/// and the payment screen all call this helper.
///
/// The field on [TicketEntity] is still useful: it carries the
/// **persisted** service charge stamped when the ticket is paid /
/// printed, so historical receipts don't drift if the operator later
/// changes the percentage.
library;

import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';

/// Compute service charge in cents for the given gross subtotal.
///
/// Swiss convention: the service charge is VAT-inclusive (Bruttopreise),
/// so we apply the percentage directly to the gross subtotal. Returns
/// 0 when the feature is disabled.
int computeServiceFeeAmount({
  required int subtotalCents,
  required RestaurantSettings? settings,
}) {
  if (settings == null) return 0;
  if (!settings.serviceChargeEnabled) return 0;
  if (subtotalCents <= 0) return 0;
  final pct = settings.serviceChargePercent;
  if (pct <= 0) return 0;
  return (subtotalCents * pct / 100).round();
}
