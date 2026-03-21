// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Online Bestellen';

  @override
  String get viewMenu => 'Speisekarte';

  @override
  String get search => 'Suchen';

  @override
  String get searchPlaceholder => 'Gerichte suchen…';

  @override
  String get allCategories => 'Alle';

  @override
  String get addToCart => 'In den Warenkorb';

  @override
  String get cart => 'Warenkorb';

  @override
  String get cartEmpty => 'Ihr Warenkorb ist leer';

  @override
  String get cartEmptyHint => 'Durchsuchen Sie die Speisekarte';

  @override
  String get browseMenu => 'Speisekarte';

  @override
  String get quantity => 'Menge';

  @override
  String get notes => 'Besondere Wünsche';

  @override
  String get notesPlaceholder => 'Allergien, Präferenzen…';

  @override
  String get orderType => 'Bestellart';

  @override
  String get dineIn => 'Im Restaurant';

  @override
  String get takeaway => 'Zum Mitnehmen';

  @override
  String get tableNumber => 'Tischnummer';

  @override
  String get tableNumberHint => 'Tischnummer eingeben';

  @override
  String get subtotal => 'Zwischensumme';

  @override
  String get vat => 'MWST';

  @override
  String vatRate(String rate) {
    return 'MwSt. $rate%';
  }

  @override
  String get total => 'Gesamt';

  @override
  String get rounding => 'Rundung';

  @override
  String get placeOrder => 'Bestellung aufgeben';

  @override
  String get orderSummary => 'Bestellübersicht';

  @override
  String get yourName => 'Ihr Name (optional)';

  @override
  String get yourNameHint => 'z.B. Maria';

  @override
  String get orderNotes => 'Notizen zur Bestellung';

  @override
  String get orderNotesHint => 'Hinweise für die Küche';

  @override
  String get confirmOrder => 'Bestellung bestätigen';

  @override
  String get orderPlaced => 'Bestellung aufgegeben!';

  @override
  String orderNumber(String number) {
    return 'Bestellung #$number';
  }

  @override
  String estimatedWait(String minutes) {
    return 'Geschätzte Wartezeit: $minutes Min.';
  }

  @override
  String get orderSentToKitchen =>
      'Ihre Bestellung wurde an die Küche gesendet.';

  @override
  String get trackOrder => 'Bestellung verfolgen';

  @override
  String get orderStatus => 'Bestellstatus';

  @override
  String get statusReceived => 'Bestellung erhalten';

  @override
  String get statusPreparing => 'In Zubereitung';

  @override
  String get statusReady => 'Fertig!';

  @override
  String get statusServed => 'Serviert';

  @override
  String get backToMenu => 'Zurück zur Speisekarte';

  @override
  String get remove => 'Entfernen';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get close => 'Schliessen';

  @override
  String get language => 'Sprache';

  @override
  String get required => 'Pflichtfeld';

  @override
  String get optional => 'Optional';

  @override
  String get outOfStock => 'Nicht verfügbar';

  @override
  String get customize => 'Anpassen';

  @override
  String get chooseOne => 'Eine Option wählen';

  @override
  String chooseUpTo(String max) {
    return 'Bis zu $max wählen';
  }

  @override
  String chooseAtLeast(String min) {
    return 'Mindestens $min wählen';
  }

  @override
  String get free => 'Gratis';

  @override
  String get itemAdded => 'Zum Warenkorb hinzugefügt';

  @override
  String get errorLoadingMenu =>
      'Menü konnte nicht geladen werden. Bitte versuchen Sie es erneut.';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get orderFailed =>
      'Bestellung fehlgeschlagen. Bitte versuchen Sie es erneut.';

  @override
  String get loading => 'Laden…';

  @override
  String get chf => 'CHF';

  @override
  String get modifiers => 'Anpassungen';

  @override
  String tableAutoFilled(String number) {
    return 'Tisch $number automatisch erkannt';
  }

  @override
  String get selectTableNumber => 'Bitte Tischnummer eingeben';

  @override
  String get continueToCheckout => 'Weiter zur Kasse';

  @override
  String get orderTypeRequired => 'Bitte Tisch oder Mitnehmen wählen';

  @override
  String itemsInCart(String count) {
    return '$count Artikel im Warenkorb';
  }
}
