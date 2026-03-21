// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Ordina Online';

  @override
  String get viewMenu => 'Vedi il menu';

  @override
  String get search => 'Cerca';

  @override
  String get searchPlaceholder => 'Cerca piatti…';

  @override
  String get allCategories => 'Tutto';

  @override
  String get addToCart => 'Aggiungi al carrello';

  @override
  String get cart => 'Carrello';

  @override
  String get cartEmpty => 'Il carrello è vuoto';

  @override
  String get cartEmptyHint => 'Sfoglia il menu e aggiungi articoli';

  @override
  String get browseMenu => 'Menu';

  @override
  String get quantity => 'Quantità';

  @override
  String get notes => 'Richieste speciali';

  @override
  String get notesPlaceholder => 'Allergie, preferenze…';

  @override
  String get orderType => 'Tipo di ordine';

  @override
  String get dineIn => 'Al tavolo';

  @override
  String get takeaway => 'Da asporto';

  @override
  String get tableNumber => 'Numero tavolo';

  @override
  String get tableNumberHint => 'Inserisci il numero del tuo tavolo';

  @override
  String get subtotal => 'Subtotale';

  @override
  String get vat => 'IVA';

  @override
  String vatRate(String rate) {
    return 'IVA $rate%';
  }

  @override
  String get total => 'Totale';

  @override
  String get rounding => 'Arrotondamento';

  @override
  String get placeOrder => 'Ordina';

  @override
  String get orderSummary => 'Riepilogo ordine';

  @override
  String get yourName => 'Il tuo nome (opzionale)';

  @override
  String get yourNameHint => 'es. Maria';

  @override
  String get orderNotes => 'Note sull\'ordine';

  @override
  String get orderNotesHint => 'Note per la cucina';

  @override
  String get confirmOrder => 'Conferma ordine';

  @override
  String get orderPlaced => 'Ordine inviato!';

  @override
  String orderNumber(String number) {
    return 'Ordine #$number';
  }

  @override
  String estimatedWait(String minutes) {
    return 'Attesa stimata: $minutes min';
  }

  @override
  String get orderSentToKitchen => 'Il tuo ordine è stato inviato in cucina.';

  @override
  String get trackOrder => 'Segui l\'ordine';

  @override
  String get orderStatus => 'Stato ordine';

  @override
  String get statusReceived => 'Ordine ricevuto';

  @override
  String get statusPreparing => 'In preparazione';

  @override
  String get statusReady => 'Pronto!';

  @override
  String get statusServed => 'Servito';

  @override
  String get backToMenu => 'Torna al menu';

  @override
  String get remove => 'Rimuovi';

  @override
  String get edit => 'Modifica';

  @override
  String get close => 'Chiudi';

  @override
  String get language => 'Lingua';

  @override
  String get required => 'Obbligatorio';

  @override
  String get optional => 'Opzionale';

  @override
  String get outOfStock => 'Non disponibile';

  @override
  String get customize => 'Personalizza';

  @override
  String get chooseOne => 'Scegli un\'opzione';

  @override
  String chooseUpTo(String max) {
    return 'Scegli fino a $max';
  }

  @override
  String chooseAtLeast(String min) {
    return 'Scegli almeno $min';
  }

  @override
  String get free => 'Gratis';

  @override
  String get itemAdded => 'Aggiunto al carrello';

  @override
  String get errorLoadingMenu => 'Impossibile caricare il menu. Riprova.';

  @override
  String get retry => 'Riprova';

  @override
  String get orderFailed => 'Ordine fallito. Riprova.';

  @override
  String get loading => 'Caricamento…';

  @override
  String get chf => 'CHF';

  @override
  String get modifiers => 'Personalizzazioni';

  @override
  String tableAutoFilled(String number) {
    return 'Tavolo $number rilevato da QR';
  }

  @override
  String get selectTableNumber => 'Inserisci il numero del tavolo';

  @override
  String get continueToCheckout => 'Vai alla cassa';

  @override
  String get orderTypeRequired => 'Seleziona al tavolo o da asporto';

  @override
  String itemsInCart(String count) {
    return '$count articolo/i nel carrello';
  }
}
