/// Riverpod providers for the PriceResolver service.
///
/// Exposes a [PriceResolver] instance backed by the app database,
/// and a configurable country code for tax resolution.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/services/price_resolver.dart';

/// Provides a [PriceResolver] instance using the shared database.
final priceResolverProvider = Provider<PriceResolver>((ref) {
  final db = ref.watch(databaseProvider);
  return PriceResolver(db);
});

/// Current country code for tax resolution.
///
/// Defaults to 'CH' (Switzerland). Change to 'DE' for German tenants.
/// This is typically set from tenant configuration at app startup.
final countryCodeProvider = StateProvider<String>((ref) => 'CH');
