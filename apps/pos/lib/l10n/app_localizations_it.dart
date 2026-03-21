// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'GastroCore POS';

  @override
  String get navHome => 'Home';

  @override
  String get navOrders => 'Ordini';

  @override
  String get navTables => 'Tavoli';

  @override
  String get navMenu => 'Menu';

  @override
  String get navShift => 'Turno';

  @override
  String get navSettings => 'Impostazioni';

  @override
  String get navReports => 'Rapporti';

  @override
  String get navKitchen => 'Cucina';

  @override
  String get posNewOrder => 'Nuovo ordine';

  @override
  String get posOrder => 'Ordine';

  @override
  String get posPayment => 'Pagamento';

  @override
  String get posCash => 'Contanti';

  @override
  String get posCard => 'Carta';

  @override
  String get posTwint => 'TWINT';

  @override
  String get posTotal => 'Totale';

  @override
  String get posSubtotal => 'Subtotale';

  @override
  String get posVat => 'IVA';

  @override
  String get posDiscount => 'Sconto';

  @override
  String get posCancel => 'Annulla';

  @override
  String get posRefund => 'Rimborso';

  @override
  String get posCharge => 'Addebita';

  @override
  String get posGiven => 'Importo dato';

  @override
  String get posChange => 'Resto';

  @override
  String get posSplitBill => 'Dividi il conto';

  @override
  String get posOrderType => 'Tipo ordine';

  @override
  String get posDineIn => 'Al tavolo';

  @override
  String get posTakeaway => 'Da asporto';

  @override
  String get posDelivery => 'Consegna';

  @override
  String get tableEmpty => 'Libero';

  @override
  String get tableOccupied => 'Occupato';

  @override
  String get tableReserved => 'Riservato';

  @override
  String get tableDirty => 'Sporco';

  @override
  String get tableMerge => 'Unire';

  @override
  String get tableTransfer => 'Trasferire';

  @override
  String tableGuest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ospiti',
      one: '1 ospite',
    );
    return '$_temp0';
  }

  @override
  String get tableNewTable => 'Nuovo tavolo';

  @override
  String get tableFloor => 'Zona';

  @override
  String get tableCapacity => 'Capacità';

  @override
  String get shiftOpen => 'Apri';

  @override
  String get shiftClose => 'Chiudi';

  @override
  String get shiftCashCount => 'Conteggio cassa';

  @override
  String get shiftDifference => 'Differenza';

  @override
  String get shiftZReport => 'Rapporto Z';

  @override
  String get shiftXReport => 'Rapporto X (intermedio)';

  @override
  String get shiftOpenShift => 'Apri turno';

  @override
  String get shiftCloseShift => 'Chiudi turno';

  @override
  String get shiftOpeningFloat => 'Fondo cassa';

  @override
  String get shiftCashIn => 'Entrata cassa';

  @override
  String get shiftCashOut => 'Uscita cassa';

  @override
  String get shiftNoActiveShift => 'Nessun turno attivo';

  @override
  String get shiftOpenCashDrawer => 'Apri cassetto cassa';

  @override
  String get receiptNo => 'N° scontrino';

  @override
  String get receiptDate => 'Data';

  @override
  String get receiptTime => 'Ora';

  @override
  String get receiptCashier => 'Cassiere';

  @override
  String get receiptThankYou => 'Grazie mille!';

  @override
  String get receiptTable => 'Tavolo';

  @override
  String get settingsPrinter => 'Stampante';

  @override
  String get settingsPayment => 'Pagamento';

  @override
  String get settingsLanguage => 'Lingua';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsBackup => 'Backup';

  @override
  String get settingsRestaurant => 'Ristorante';

  @override
  String get settingsTax => 'Tassa (IVA)';

  @override
  String get settingsReceipt => 'Scontrino';

  @override
  String get settingsAppearance => 'Aspetto';

  @override
  String get settingsAbout => 'Informazioni';

  @override
  String get settingsDemoData => 'Dati demo';

  @override
  String get actionSave => 'Salva';

  @override
  String get actionCancel => 'Annulla';

  @override
  String get actionDelete => 'Elimina';

  @override
  String get actionEdit => 'Modifica';

  @override
  String get actionAdd => 'Aggiungi';

  @override
  String get actionSearch => 'Cerca';

  @override
  String get actionFilter => 'Filtra';

  @override
  String get actionConfirm => 'OK';

  @override
  String get actionClose => 'Chiudi';

  @override
  String get actionBack => 'Indietro';

  @override
  String get actionPrint => 'Stampa';

  @override
  String get actionRefresh => 'Aggiorna';

  @override
  String get statusError => 'Errore';

  @override
  String get statusSuccess => 'Riuscito';

  @override
  String get statusLoading => 'Caricamento...';

  @override
  String get statusNoData => 'Nessun dato';

  @override
  String get statusOffline => 'Non in linea';

  @override
  String get statusOnline => 'In linea';

  @override
  String get menuCategory => 'Categoria';

  @override
  String get menuProduct => 'Prodotto';

  @override
  String get menuPrice => 'Prezzo';

  @override
  String get menuModifier => 'Opzione';

  @override
  String get menuActive => 'Attivo';

  @override
  String get menuInactive => 'Inattivo';

  @override
  String get orderHistory => 'Storico ordini';

  @override
  String get orderStatus => 'Stato';

  @override
  String get orderStatusOpen => 'Aperto';

  @override
  String get orderStatusPaid => 'Pagato';

  @override
  String get orderStatusCancelled => 'Annullato';

  @override
  String get orderStatusRefunded => 'Rimborsato';

  @override
  String get dashboardDailyRevenue => 'Fatturato giornaliero';

  @override
  String get dashboardOrders => 'Ordini';

  @override
  String get dashboardAvgOrder => 'Ordine medio';

  @override
  String get dashboardTableOccupancy => 'Tasso occupazione';

  @override
  String get dashboardRecentOrders => 'Ordini recenti';

  @override
  String get dashboardHourlySales => 'Vendite orarie';

  @override
  String get floorPlan => 'Pianta sala';

  @override
  String get editMode => 'Modalità modifica';

  @override
  String get confirmDelete => 'Conferma eliminazione';

  @override
  String get confirmDeleteMessage => 'Vuoi davvero eliminare questo elemento?';

  @override
  String get pinLogin => 'Inserisci PIN';

  @override
  String get pinWrong => 'PIN errato';

  @override
  String get shiftStatusOpen => 'Turno aperto';

  @override
  String get shiftNoShiftTapToOpen => 'Nessun turno – tocca per aprire';

  @override
  String get quickActionNewOrder => 'Nuovo ordine';

  @override
  String get quickActionFloorPlan => 'Pianta sala';

  @override
  String get quickActionOpenShift => 'Apri turno';

  @override
  String get quickActionCloseShift => 'Chiudi turno';

  @override
  String get quickActionOrderHistory => 'Storico ordini';

  @override
  String get navCrm => 'Clienti';

  @override
  String get navReservations => 'Prenotazioni';

  @override
  String get crmCustomers => 'Clienti';

  @override
  String get crmNewCustomer => 'Nuovo cliente';

  @override
  String get crmCustomerName => 'Nome';

  @override
  String get crmPhone => 'Telefono';

  @override
  String get crmEmail => 'Email';

  @override
  String get crmBirthday => 'Compleanno';

  @override
  String get crmNotes => 'Note';

  @override
  String get crmLoyaltyPoints => 'Punti fedeltà';

  @override
  String get crmLoyaltyBalance => 'Saldo punti';

  @override
  String get crmAddPoints => 'Aggiungi punti';

  @override
  String get crmRedeemPoints => 'Riscatta punti';

  @override
  String get crmTotalVisits => 'Visite';

  @override
  String get crmTotalSpent => 'Totale speso';

  @override
  String get crmLastVisit => 'Ultima visita';

  @override
  String get crmSearchCustomers => 'Cerca clienti';

  @override
  String get crmNoCustomers => 'Nessun cliente';

  @override
  String get crmLoyaltyEarn => 'Guadagna punti';

  @override
  String get crmLoyaltyRedeem => 'Riscatta';

  @override
  String get crmLoyaltyAdjust => 'Aggiusta punti';

  @override
  String get crmLoyaltyHistory => 'Storico punti';

  @override
  String get reservationNew => 'Nuova prenotazione';

  @override
  String get reservationDate => 'Data';

  @override
  String get reservationTime => 'Orario';

  @override
  String get reservationGuests => 'Ospiti';

  @override
  String get reservationTable => 'Tavolo';

  @override
  String get reservationStatus => 'Stato';

  @override
  String get reservationStatusConfirmed => 'Confermata';

  @override
  String get reservationStatusPending => 'In attesa';

  @override
  String get reservationStatusCancelled => 'Annullata';

  @override
  String get reservationStatusSeated => 'Seduta';

  @override
  String get reservationStatusNoShow => 'Assente';

  @override
  String get reservationCustomerName => 'Nome ospite';

  @override
  String get reservationPhone => 'Telefono';

  @override
  String get reservationNotes => 'Note';

  @override
  String get reservationConflict => 'Conflitto tavolo rilevato';

  @override
  String get reservationNoReservations => 'Nessuna prenotazione';

  @override
  String get reservationToday => 'Oggi';

  @override
  String get reservationCalendar => 'Calendario';

  @override
  String get reservationDuration => 'Durata (min)';

  @override
  String get reservationCheckConflict => 'Controlla conflitti';
}
