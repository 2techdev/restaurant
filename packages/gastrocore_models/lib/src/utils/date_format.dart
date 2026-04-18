/// Lightweight locale-aware date/time formatters without pulling a
/// full `intl` dependency into the pure-Dart [gastrocore_models] package.
/// Flutter apps that already depend on `intl` may prefer
/// [DateFormat.yMd] for richer locale coverage; this helper exists so that
/// receipt printing and sync-layer log lines can emit consistent strings
/// without a Flutter binding.
library;

/// Supported date format styles.
///
/// * [shortDate]  — DE/FR/IT-CH: 17.04.2026 · TR: 17.04.2026 · EN: 2026-04-17
/// * [longDate]   — DE/FR/IT-CH: 17. April 2026 / 17 avril 2026 / 17 aprile 2026 · TR: 17 Nisan 2026 · EN: April 17, 2026
/// * [time24]     — 14:05 (all locales — Switzerland and Turkey are 24h)
/// * [dateTime]   — shortDate + " " + time24
enum DateStyle { shortDate, longDate, time24, dateTime }

/// Format [dt] for [languageCode]. If [languageCode] is unknown, falls back
/// to the ISO 8601-style used for `en` (unambiguous across regions).
String formatDate(DateTime dt, String languageCode,
    [DateStyle style = DateStyle.shortDate]) {
  switch (style) {
    case DateStyle.shortDate:
      return _shortDate(dt, languageCode);
    case DateStyle.longDate:
      return _longDate(dt, languageCode);
    case DateStyle.time24:
      return _time24(dt);
    case DateStyle.dateTime:
      return '${_shortDate(dt, languageCode)} ${_time24(dt)}';
  }
}

String _shortDate(DateTime dt, String languageCode) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final y = dt.year.toString().padLeft(4, '0');
  switch (languageCode) {
    case 'de':
    case 'fr':
    case 'it':
    case 'tr':
      return '$d.$m.$y';
    case 'en':
    default:
      return '$y-$m-$d';
  }
}

String _longDate(DateTime dt, String languageCode) {
  final d = dt.day;
  final m = _monthName(dt.month, languageCode);
  final y = dt.year;
  switch (languageCode) {
    case 'de':
      return '$d. $m $y';
    case 'fr':
    case 'it':
    case 'tr':
      return '$d $m $y';
    case 'en':
    default:
      return '$m $d, $y';
  }
}

String _time24(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$h:$mm';
}

String _monthName(int month, String languageCode) {
  const names = <String, List<String>>{
    'de': [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
    ],
    'fr': [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ],
    'it': [
      'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno',
      'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre',
    ],
    'tr': [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ],
    'en': [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ],
  };
  final list = names[languageCode] ?? names['en']!;
  return list[month - 1];
}
