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

Locale _toLocale(AppLanguage language) => switch (language) {
      AppLanguage.de => const Locale('de'),
      AppLanguage.fr => const Locale('fr'),
      AppLanguage.it => const Locale('it'),
      AppLanguage.en => const Locale('en'),
    };
