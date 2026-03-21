/// Locale (language) state provider.
/// Persists selection in shared_preferences.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLocaleKey = 'gastrocore_online_locale';

final localeProvider =
    StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en')) {
    _restore();
  }

  static const _supported = [
    Locale('en'),
    Locale('de'),
    Locale('fr'),
    Locale('it'),
  ];

  List<Locale> get supportedLocales => _supported;

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocaleKey);
    if (code != null) {
      final locale = _supported.where((l) => l.languageCode == code);
      if (locale.isNotEmpty) state = locale.first;
    }
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, locale.languageCode);
  }
}
