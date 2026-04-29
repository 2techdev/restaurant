// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'GastroCore Dashboard';

  @override
  String get login => 'Anmelden';

  @override
  String get logout => 'Abmelden';

  @override
  String get email => 'E-Mail-Adresse';

  @override
  String get password => 'Passwort';

  @override
  String get rememberMe => 'Angemeldet bleiben';

  @override
  String get loginSubtitle => 'Zugang für Restaurant-Manager';

  @override
  String get loginError => 'Ungültige E-Mail oder Passwort';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get orders => 'Bestellungen';

  @override
  String get menu => 'Speisekarte';

  @override
  String get reports => 'Berichte';

  @override
  String get settings => 'Einstellungen';

  @override
  String get totalRevenue => 'Umsatz heute';

  @override
  String get orderCount => 'Bestellungen';

  @override
  String get avgTicket => 'Ø Bon';

  @override
  String get activeOrders => 'Aktive Bestellungen';

  @override
  String get tablesOccupied => 'Besetzte Tische';

  @override
  String get staffOnShift => 'Personal in Schicht';

  @override
  String get topItems => 'Top Artikel heute';

  @override
  String get revenueChart => 'Umsatzverlauf';

  @override
  String get last7Days => 'Letzte 7 Tage';

  @override
  String get last30Days => 'Letzte 30 Tage';

  @override
  String get last90Days => 'Letzte 90 Tage';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get allOrders => 'Alle Bestellungen';

  @override
  String get filterByDate => 'Nach Datum filtern';

  @override
  String get filterByStatus => 'Nach Status filtern';

  @override
  String get exportCsv => 'CSV Export';

  @override
  String orderNumber(String number) {
    return 'Bestellung #$number';
  }

  @override
  String get paid => 'Bezahlt';

  @override
  String get open => 'Offen';

  @override
  String get preparing => 'In Zubereitung';

  @override
  String get closed => 'Geschlossen';

  @override
  String get cancelled => 'Storniert';

  @override
  String get dineIn => 'Im Restaurant';

  @override
  String get takeaway => 'Takeaway';

  @override
  String get categories => 'Kategorien';

  @override
  String get products => 'Produkte';

  @override
  String get addProduct => 'Produkt hinzufügen';

  @override
  String get addCategory => 'Kategorie hinzufügen';

  @override
  String get editProduct => 'Produkt bearbeiten';

  @override
  String get available => 'Verfügbar';

  @override
  String get price => 'Preis';

  @override
  String get taxGroup => 'Steuergruppe';

  @override
  String get dailyReport => 'Täglich';

  @override
  String get weeklyReport => 'Wöchentlich';

  @override
  String get monthlyReport => 'Monatlich';

  @override
  String get salesByCategory => 'Umsatz nach Kategorie';

  @override
  String get paymentBreakdown => 'Zahlungsmethoden';

  @override
  String get staffPerformance => 'Personalleistung';

  @override
  String get mwstReport => 'MWST-Abrechnung';

  @override
  String get restaurantInfo => 'Restaurant-Informationen';

  @override
  String get printerConfig => 'Druckereinstellungen';

  @override
  String get taxSettings => 'Steuereinstellungen';

  @override
  String get userManagement => 'Benutzerverwaltung';

  @override
  String get save => 'Speichern';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get add => 'Hinzufügen';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get delete => 'Löschen';

  @override
  String get from => 'Von';

  @override
  String get to => 'Bis';

  @override
  String get apply => 'Anwenden';

  @override
  String get today => 'Heute';

  @override
  String get yesterday => 'Gestern';

  @override
  String get thisWeek => 'Diese Woche';

  @override
  String get thisMonth => 'Dieser Monat';

  @override
  String get chf => 'CHF';

  @override
  String get loading => 'Laden…';

  @override
  String get noData => 'Keine Daten';

  @override
  String get error => 'Fehler';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get lightMode => 'Light Mode';

  @override
  String get language => 'Sprache';

  @override
  String get copiedToClipboard => 'In Zwischenablage kopiert';

  @override
  String get saveSuccess => 'Änderungen gespeichert';
}
