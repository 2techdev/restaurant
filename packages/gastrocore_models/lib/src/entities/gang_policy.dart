/// Runtime policy for the Gang / course workflow.
///
/// Centralises every "is this gang enabled" / "what's the label" decision so
/// POS, Waiter, and KDS all agree on the same rules. Apps should call into
/// [GangPolicy] rather than reading [RestaurantSettings] fields directly.
library;

import 'gang_entity.dart';
import 'restaurant_settings.dart';

abstract final class GangPolicy {
  /// True if the Gang workflow is turned on for this tenant.
  static bool enabled(RestaurantSettings settings) =>
      settings.normalized().gangsEnabled;

  /// Number of gang slots the UI should show. Always between
  /// [RestaurantSettingsLimits.minGangs] and
  /// [RestaurantSettingsLimits.maxGangs].
  static int count(RestaurantSettings settings) =>
      settings.normalized().maxGangs;

  /// Label for the gang at a 0-based [index]. Falls back to `"Gang N"` when
  /// [index] is out of range so callers never see an empty string.
  static String labelFor(RestaurantSettings settings, int index) {
    final n = settings.normalized();
    if (index < 0) return 'Gang ${index + 1}';
    if (index < n.gangLabels.length) return n.gangLabels[index];
    return 'Gang ${index + 1}';
  }

  /// Label for the gang at a 1-based [position]. Thin wrapper around
  /// [labelFor] for call sites that already use [Gang.position].
  static String labelForPosition(RestaurantSettings settings, int position) =>
      labelFor(settings, position - 1);

  /// Resolved label for a baseline [Gang] enum value.
  static String labelForGang(RestaurantSettings settings, Gang gang) =>
      labelForPosition(settings, gang.position);

  /// All enabled labels in display order. Empty when
  /// [enabled(settings)] is false.
  static List<String> labels(RestaurantSettings settings) {
    final n = settings.normalized();
    if (!n.gangsEnabled) return const [];
    return List<String>.of(n.gangLabels);
  }
}
