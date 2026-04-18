/// Derives the active [Locale] from the persisted [AppSettings.language].
///
/// Watched by [GastroCoreApp] so that changing the language in Settings
/// immediately rebuilds [MaterialApp] with the new locale.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/features/settings/domain/entities/app_settings.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';

/// Returns the current [Locale] based on the saved [AppLanguage].
/// Falls back to German if settings are still loading.
final localeProvider = Provider<Locale>((ref) {
  final settings = ref.watch(appSettingsProvider);
  final language = settings.valueOrNull?.language ?? AppLanguage.de;
  return _toLocale(language);
});

/// Maps an [AppLanguage] to a [Locale]. Swiss German uses the `de-CH`
/// script variant so that `intl` formatters pick the Swiss date/number
/// conventions (e.g. thousand separators, 17.04.2026, apostrophes in
/// grouped numbers) rather than the default German (de-DE) ones.
Locale _toLocale(AppLanguage language) => switch (language) {
      AppLanguage.de => const Locale('de', 'CH'),
      AppLanguage.tr => const Locale('tr'),
      AppLanguage.en => const Locale('en'),
      AppLanguage.fr => const Locale('fr', 'CH'),
      AppLanguage.it => const Locale('it', 'CH'),
    };
