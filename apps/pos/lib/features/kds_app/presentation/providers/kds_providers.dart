/// Shared Riverpod providers for the KDS standalone app.
///
/// These providers are shared between [KdsMainScreen],
/// [KdsStationFilterScreen], and [KdsSettingsScreen].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Currently active station filter (null = all stations).
final kdsStationFilterProvider = StateProvider<String?>((ref) => null);

/// Whether large-font mode is active.
final kdsLargeFontProvider = StateProvider<bool>((ref) => false);

/// Minutes after which a ticket is considered late (turns red).
final kdsLateThresholdProvider = StateProvider<int>((ref) => 10);
