// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'GastroCore Dashboard';

  @override
  String get login => 'Accedi';

  @override
  String get logout => 'Esci';

  @override
  String get email => 'Indirizzo e-mail';

  @override
  String get password => 'Password';

  @override
  String get rememberMe => 'Ricordami';

  @override
  String get loginSubtitle => 'Accesso per i responsabili del ristorante';

  @override
  String get loginError => 'E-mail o password non validi';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get orders => 'Ordini';

  @override
  String get menu => 'Menu';

  @override
  String get reports => 'Rapporti';

  @override
  String get settings => 'Impostazioni';

  @override
  String get totalRevenue => 'Fatturato oggi';

  @override
  String get orderCount => 'Ordini';

  @override
  String get avgTicket => 'Scontrino medio';

  @override
  String get activeOrders => 'Ordini attivi';

  @override
  String get tablesOccupied => 'Tavoli occupati';

  @override
  String get staffOnShift => 'Personale in turno';

  @override
  String get topItems => 'Articoli più venduti oggi';

  @override
  String get revenueChart => 'Andamento del fatturato';

  @override
  String get last7Days => 'Ultimi 7 giorni';

  @override
  String get last30Days => 'Ultimi 30 giorni';

  @override
  String get last90Days => 'Ultimi 90 giorni';

  @override
  String get refresh => 'Aggiorna';

  @override
  String get allOrders => 'Tutti gli ordini';

  @override
  String get filterByDate => 'Filtra per data';

  @override
  String get filterByStatus => 'Filtra per stato';

  @override
  String get exportCsv => 'Esporta CSV';

  @override
  String orderNumber(String number) {
    return 'Ordine #$number';
  }

  @override
  String get paid => 'Pagato';

  @override
  String get open => 'Aperto';

  @override
  String get preparing => 'In preparazione';

  @override
  String get closed => 'Chiuso';

  @override
  String get cancelled => 'Annullato';

  @override
  String get dineIn => 'In loco';

  @override
  String get takeaway => 'Da asporto';

  @override
  String get categories => 'Categorie';

  @override
  String get products => 'Prodotti';

  @override
  String get addProduct => 'Aggiungi prodotto';

  @override
  String get addCategory => 'Aggiungi categoria';

  @override
  String get editProduct => 'Modifica prodotto';

  @override
  String get available => 'Disponibile';

  @override
  String get price => 'Prezzo';

  @override
  String get taxGroup => 'Gruppo IVA';

  @override
  String get dailyReport => 'Giornaliero';

  @override
  String get weeklyReport => 'Settimanale';

  @override
  String get monthlyReport => 'Mensile';

  @override
  String get salesByCategory => 'Vendite per categoria';

  @override
  String get paymentBreakdown => 'Metodi di pagamento';

  @override
  String get staffPerformance => 'Performance del personale';

  @override
  String get mwstReport => 'Rapporto IVA';

  @override
  String get restaurantInfo => 'Info ristorante';

  @override
  String get printerConfig => 'Configurazione stampante';

  @override
  String get taxSettings => 'Impostazioni IVA';

  @override
  String get userManagement => 'Gestione utenti';

  @override
  String get save => 'Salva';

  @override
  String get cancel => 'Annulla';

  @override
  String get add => 'Aggiungi';

  @override
  String get edit => 'Modifica';

  @override
  String get delete => 'Elimina';

  @override
  String get from => 'Da';

  @override
  String get to => 'A';

  @override
  String get apply => 'Applica';

  @override
  String get today => 'Oggi';

  @override
  String get yesterday => 'Ieri';

  @override
  String get thisWeek => 'Questa settimana';

  @override
  String get thisMonth => 'Questo mese';

  @override
  String get chf => 'CHF';

  @override
  String get loading => 'Caricamento…';

  @override
  String get noData => 'Nessun dato';

  @override
  String get error => 'Errore';

  @override
  String get retry => 'Riprova';

  @override
  String get darkMode => 'Modalità scura';

  @override
  String get lightMode => 'Modalità chiara';

  @override
  String get language => 'Lingua';

  @override
  String get copiedToClipboard => 'Copiato negli appunti';

  @override
  String get saveSuccess => 'Modifiche salvate';
}
