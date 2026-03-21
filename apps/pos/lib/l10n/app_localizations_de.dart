// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'GastroCore POS';

  @override
  String get navHome => 'Startseite';

  @override
  String get navOrders => 'Bestellungen';

  @override
  String get navTables => 'Tische';

  @override
  String get navMenu => 'Menü';

  @override
  String get navShift => 'Schicht';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get navReports => 'Berichte';

  @override
  String get navKitchen => 'Küche';

  @override
  String get posNewOrder => 'Neue Bestellung';

  @override
  String get posOrder => 'Bestellung';

  @override
  String get posPayment => 'Zahlung';

  @override
  String get posCash => 'Bar';

  @override
  String get posCard => 'Karte';

  @override
  String get posTwint => 'TWINT';

  @override
  String get posTotal => 'Total';

  @override
  String get posSubtotal => 'Zwischentotal';

  @override
  String get posVat => 'MWST';

  @override
  String get posDiscount => 'Rabatt';

  @override
  String get posCancel => 'Abbrechen';

  @override
  String get posRefund => 'Rückerstattung';

  @override
  String get posCharge => 'Belasten';

  @override
  String get posGiven => 'Gegeben';

  @override
  String get posChange => 'Rückgeld';

  @override
  String get posSplitBill => 'Rechnung teilen';

  @override
  String get posOrderType => 'Bestellart';

  @override
  String get posDineIn => 'Vor Ort';

  @override
  String get posTakeaway => 'Zum Mitnehmen';

  @override
  String get posDelivery => 'Lieferung';

  @override
  String get tableEmpty => 'Frei';

  @override
  String get tableOccupied => 'Belegt';

  @override
  String get tableReserved => 'Reserviert';

  @override
  String get tableDirty => 'Schmutzig';

  @override
  String get tableMerge => 'Zusammenführen';

  @override
  String get tableTransfer => 'Umbuchen';

  @override
  String tableGuest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Gäste',
      one: '1 Gast',
    );
    return '$_temp0';
  }

  @override
  String get tableNewTable => 'Neuer Tisch';

  @override
  String get tableFloor => 'Bereich';

  @override
  String get tableCapacity => 'Kapazität';

  @override
  String get shiftOpen => 'Öffnen';

  @override
  String get shiftClose => 'Schliessen';

  @override
  String get shiftCashCount => 'Kassenstand';

  @override
  String get shiftDifference => 'Differenz';

  @override
  String get shiftZReport => 'Z-Rapport';

  @override
  String get shiftXReport => 'X-Rapport';

  @override
  String get shiftOpenShift => 'Schicht öffnen';

  @override
  String get shiftCloseShift => 'Schicht schliessen';

  @override
  String get shiftOpeningFloat => 'Eröffnungsbestand';

  @override
  String get shiftCashIn => 'Kassenzugang';

  @override
  String get shiftCashOut => 'Kassenentnahme';

  @override
  String get shiftNoActiveShift => 'Keine aktive Schicht';

  @override
  String get shiftOpenCashDrawer => 'Kassenlade öffnen';

  @override
  String get receiptNo => 'Bon-Nr.';

  @override
  String get receiptDate => 'Datum';

  @override
  String get receiptTime => 'Zeit';

  @override
  String get receiptCashier => 'Kassierer';

  @override
  String get receiptThankYou => 'Vielen Dank!';

  @override
  String get receiptTable => 'Tisch';

  @override
  String get settingsPrinter => 'Drucker';

  @override
  String get settingsPayment => 'Zahlung';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsTheme => 'Design';

  @override
  String get settingsBackup => 'Sicherung';

  @override
  String get settingsRestaurant => 'Restaurant';

  @override
  String get settingsTax => 'Steuer (MWST)';

  @override
  String get settingsReceipt => 'Beleg';

  @override
  String get settingsAppearance => 'Erscheinungsbild';

  @override
  String get settingsAbout => 'Über';

  @override
  String get settingsDemoData => 'Demodaten';

  @override
  String get actionSave => 'Speichern';

  @override
  String get actionCancel => 'Abbrechen';

  @override
  String get actionDelete => 'Löschen';

  @override
  String get actionEdit => 'Bearbeiten';

  @override
  String get actionAdd => 'Hinzufügen';

  @override
  String get actionSearch => 'Suchen';

  @override
  String get actionFilter => 'Filtern';

  @override
  String get actionConfirm => 'OK';

  @override
  String get actionClose => 'Schliessen';

  @override
  String get actionBack => 'Zurück';

  @override
  String get actionPrint => 'Drucken';

  @override
  String get actionRefresh => 'Aktualisieren';

  @override
  String get statusError => 'Fehler';

  @override
  String get statusSuccess => 'Erfolgreich';

  @override
  String get statusLoading => 'Laden...';

  @override
  String get statusNoData => 'Keine Daten';

  @override
  String get statusOffline => 'Offline';

  @override
  String get statusOnline => 'Online';

  @override
  String get menuCategory => 'Kategorie';

  @override
  String get menuProduct => 'Produkt';

  @override
  String get menuPrice => 'Preis';

  @override
  String get menuModifier => 'Zusatz';

  @override
  String get menuActive => 'Aktiv';

  @override
  String get menuInactive => 'Inaktiv';

  @override
  String get orderHistory => 'Bestellungshistorie';

  @override
  String get orderStatus => 'Status';

  @override
  String get orderStatusOpen => 'Offen';

  @override
  String get orderStatusPaid => 'Bezahlt';

  @override
  String get orderStatusCancelled => 'Storniert';

  @override
  String get orderStatusRefunded => 'Erstattet';

  @override
  String get dashboardDailyRevenue => 'Tagesumsatz';

  @override
  String get dashboardOrders => 'Bestellungen';

  @override
  String get dashboardAvgOrder => 'Ø Bestellung';

  @override
  String get dashboardTableOccupancy => 'Tischauslastung';

  @override
  String get dashboardRecentOrders => 'Letzte Bestellungen';

  @override
  String get dashboardHourlySales => 'Stündlicher Umsatz';

  @override
  String get floorPlan => 'Saalplan';

  @override
  String get editMode => 'Bearbeitungsmodus';

  @override
  String get confirmDelete => 'Löschen bestätigen';

  @override
  String get confirmDeleteMessage =>
      'Möchten Sie diesen Eintrag wirklich löschen?';

  @override
  String get pinLogin => 'PIN eingeben';

  @override
  String get pinWrong => 'Falscher PIN';

  @override
  String get shiftStatusOpen => 'Schicht offen';

  @override
  String get shiftNoShiftTapToOpen => 'Keine Schicht – tippen zum Öffnen';

  @override
  String get quickActionNewOrder => 'Neue Bestellung';

  @override
  String get quickActionFloorPlan => 'Saalplan';

  @override
  String get quickActionOpenShift => 'Schicht öffnen';

  @override
  String get quickActionCloseShift => 'Schicht schliessen';

  @override
  String get quickActionOrderHistory => 'Bestellungshistorie';

  @override
  String get navReservations => 'Reservierungen';

  @override
  String get reservationList => 'Reservierungen';

  @override
  String get reservationCalendar => 'Kalender';

  @override
  String get reservationNew => 'Neue Reservierung';

  @override
  String get reservationEdit => 'Reservierung bearbeiten';

  @override
  String get reservationToday => 'Heute';

  @override
  String get reservationNoUpcoming => 'Keine bevorstehenden Reservierungen';

  @override
  String get reservationNoReservations => 'Keine Reservierungen für diesen Tag';

  @override
  String get reservationCustomerInfo => 'Gastinformationen';

  @override
  String get reservationCustomerName => 'Gastname';

  @override
  String get reservationCustomerPhone => 'Telefon';

  @override
  String get reservationCustomerEmail => 'E-Mail';

  @override
  String get reservationDateTime => 'Datum & Uhrzeit';

  @override
  String get reservationDate => 'Datum';

  @override
  String get reservationTime => 'Uhrzeit';

  @override
  String get reservationPartySize => 'Personenanzahl';

  @override
  String get reservationTable => 'Tisch';

  @override
  String get reservationTableOptional => 'Tisch (optional)';

  @override
  String get reservationNoTable => 'Kein Tisch zugewiesen';

  @override
  String get reservationNotes => 'Bemerkungen';

  @override
  String get reservationMeta => 'Buchungsinfo';

  @override
  String get reservationChannel => 'Quelle';

  @override
  String get reservationStatus => 'Status';

  @override
  String get reservationChangeStatus => 'Status ändern';

  @override
  String get reservationChangeEndTime => 'Endzeit ändern';

  @override
  String get reservationChannelWalkIn => 'Walk-in';

  @override
  String get reservationChannelOnline => 'Online';

  @override
  String get reservationChannelPhone => 'Telefon';

  @override
  String get reservationStatusPending => 'Ausstehend';

  @override
  String get reservationStatusConfirmed => 'Bestätigt';

  @override
  String get reservationStatusSeated => 'Platziert';

  @override
  String get reservationStatusCancelled => 'Storniert';

  @override
  String get reservationStatusNoShow => 'No-show';

  @override
  String get reservationConfirm => 'Bestätigen';

  @override
  String get reservationSeat => 'Platzieren';

  @override
  String get reservationNoShow => 'No-show';

  @override
  String get reservationCancel => 'Reservierung stornieren';

  @override
  String get reservationViewDay => 'Tag';

  @override
  String get reservationViewWeek => 'Woche';

  @override
  String get reservationNameRequired => 'Gastname ist erforderlich';

  @override
  String get reservationErrorTimeRange =>
      'Endzeit muss nach der Startzeit liegen';

  @override
  String get reservationErrorConflict =>
      'Dieser Tisch ist zu diesem Zeitpunkt bereits reserviert';
}
