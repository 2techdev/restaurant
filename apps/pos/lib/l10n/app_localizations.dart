import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('fr'),
    Locale('it'),
  ];

  /// App title
  ///
  /// In de, this message translates to:
  /// **'GastroCore POS'**
  String get appTitle;

  /// Navigation: Home
  ///
  /// In de, this message translates to:
  /// **'Startseite'**
  String get navHome;

  /// Navigation: Orders
  ///
  /// In de, this message translates to:
  /// **'Bestellungen'**
  String get navOrders;

  /// Navigation: Tables
  ///
  /// In de, this message translates to:
  /// **'Tische'**
  String get navTables;

  /// Navigation: Menu
  ///
  /// In de, this message translates to:
  /// **'Menü'**
  String get navMenu;

  /// Navigation: Shift
  ///
  /// In de, this message translates to:
  /// **'Schicht'**
  String get navShift;

  /// Navigation: Settings
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get navSettings;

  /// Navigation: Reports
  ///
  /// In de, this message translates to:
  /// **'Berichte'**
  String get navReports;

  /// Navigation: Kitchen
  ///
  /// In de, this message translates to:
  /// **'Küche'**
  String get navKitchen;

  /// POS: New Order
  ///
  /// In de, this message translates to:
  /// **'Neue Bestellung'**
  String get posNewOrder;

  /// POS: Order
  ///
  /// In de, this message translates to:
  /// **'Bestellung'**
  String get posOrder;

  /// POS: Payment
  ///
  /// In de, this message translates to:
  /// **'Zahlung'**
  String get posPayment;

  /// POS: Cash
  ///
  /// In de, this message translates to:
  /// **'Bar'**
  String get posCash;

  /// POS: Card
  ///
  /// In de, this message translates to:
  /// **'Karte'**
  String get posCard;

  /// POS: TWINT
  ///
  /// In de, this message translates to:
  /// **'TWINT'**
  String get posTwint;

  /// POS: Total
  ///
  /// In de, this message translates to:
  /// **'Total'**
  String get posTotal;

  /// POS: Subtotal
  ///
  /// In de, this message translates to:
  /// **'Zwischentotal'**
  String get posSubtotal;

  /// POS: VAT
  ///
  /// In de, this message translates to:
  /// **'MWST'**
  String get posVat;

  /// POS: Discount
  ///
  /// In de, this message translates to:
  /// **'Rabatt'**
  String get posDiscount;

  /// POS: Cancel
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get posCancel;

  /// POS: Refund
  ///
  /// In de, this message translates to:
  /// **'Rückerstattung'**
  String get posRefund;

  /// POS: Charge
  ///
  /// In de, this message translates to:
  /// **'Belasten'**
  String get posCharge;

  /// POS: Amount given
  ///
  /// In de, this message translates to:
  /// **'Gegeben'**
  String get posGiven;

  /// POS: Change
  ///
  /// In de, this message translates to:
  /// **'Rückgeld'**
  String get posChange;

  /// POS: Split bill
  ///
  /// In de, this message translates to:
  /// **'Rechnung teilen'**
  String get posSplitBill;

  /// POS: Order type
  ///
  /// In de, this message translates to:
  /// **'Bestellart'**
  String get posOrderType;

  /// POS: Dine in
  ///
  /// In de, this message translates to:
  /// **'Vor Ort'**
  String get posDineIn;

  /// POS: Takeaway
  ///
  /// In de, this message translates to:
  /// **'Zum Mitnehmen'**
  String get posTakeaway;

  /// POS: Delivery
  ///
  /// In de, this message translates to:
  /// **'Lieferung'**
  String get posDelivery;

  /// Table: Empty/Free
  ///
  /// In de, this message translates to:
  /// **'Frei'**
  String get tableEmpty;

  /// Table: Occupied
  ///
  /// In de, this message translates to:
  /// **'Belegt'**
  String get tableOccupied;

  /// Table: Reserved
  ///
  /// In de, this message translates to:
  /// **'Reserviert'**
  String get tableReserved;

  /// Table: Dirty
  ///
  /// In de, this message translates to:
  /// **'Schmutzig'**
  String get tableDirty;

  /// Table: Merge
  ///
  /// In de, this message translates to:
  /// **'Zusammenführen'**
  String get tableMerge;

  /// Table: Transfer
  ///
  /// In de, this message translates to:
  /// **'Umbuchen'**
  String get tableTransfer;

  /// Table: Guest count
  ///
  /// In de, this message translates to:
  /// **'{count,plural, one{1 Gast} other{{count} Gäste}}'**
  String tableGuest(int count);

  /// Table: New table
  ///
  /// In de, this message translates to:
  /// **'Neuer Tisch'**
  String get tableNewTable;

  /// Table: Floor/Zone
  ///
  /// In de, this message translates to:
  /// **'Bereich'**
  String get tableFloor;

  /// Table: Capacity
  ///
  /// In de, this message translates to:
  /// **'Kapazität'**
  String get tableCapacity;

  /// Shift: Open
  ///
  /// In de, this message translates to:
  /// **'Öffnen'**
  String get shiftOpen;

  /// Shift: Close
  ///
  /// In de, this message translates to:
  /// **'Schliessen'**
  String get shiftClose;

  /// Shift: Cash count
  ///
  /// In de, this message translates to:
  /// **'Kassenstand'**
  String get shiftCashCount;

  /// Shift: Difference
  ///
  /// In de, this message translates to:
  /// **'Differenz'**
  String get shiftDifference;

  /// Shift: Z-Report
  ///
  /// In de, this message translates to:
  /// **'Z-Rapport'**
  String get shiftZReport;

  /// Shift: X-Report (interim)
  ///
  /// In de, this message translates to:
  /// **'X-Rapport'**
  String get shiftXReport;

  /// Shift: Open shift
  ///
  /// In de, this message translates to:
  /// **'Schicht öffnen'**
  String get shiftOpenShift;

  /// Shift: Close shift
  ///
  /// In de, this message translates to:
  /// **'Schicht schliessen'**
  String get shiftCloseShift;

  /// Shift: Opening float
  ///
  /// In de, this message translates to:
  /// **'Eröffnungsbestand'**
  String get shiftOpeningFloat;

  /// Shift: Cash in
  ///
  /// In de, this message translates to:
  /// **'Kassenzugang'**
  String get shiftCashIn;

  /// Shift: Cash out
  ///
  /// In de, this message translates to:
  /// **'Kassenentnahme'**
  String get shiftCashOut;

  /// Shift: No active shift
  ///
  /// In de, this message translates to:
  /// **'Keine aktive Schicht'**
  String get shiftNoActiveShift;

  /// Shift: Open cash drawer
  ///
  /// In de, this message translates to:
  /// **'Kassenlade öffnen'**
  String get shiftOpenCashDrawer;

  /// Receipt: Receipt number
  ///
  /// In de, this message translates to:
  /// **'Bon-Nr.'**
  String get receiptNo;

  /// Receipt: Date
  ///
  /// In de, this message translates to:
  /// **'Datum'**
  String get receiptDate;

  /// Receipt: Time
  ///
  /// In de, this message translates to:
  /// **'Zeit'**
  String get receiptTime;

  /// Receipt: Cashier
  ///
  /// In de, this message translates to:
  /// **'Kassierer'**
  String get receiptCashier;

  /// Receipt: Thank you
  ///
  /// In de, this message translates to:
  /// **'Vielen Dank!'**
  String get receiptThankYou;

  /// Receipt: Table
  ///
  /// In de, this message translates to:
  /// **'Tisch'**
  String get receiptTable;

  /// Settings: Printer
  ///
  /// In de, this message translates to:
  /// **'Drucker'**
  String get settingsPrinter;

  /// Settings: Payment
  ///
  /// In de, this message translates to:
  /// **'Zahlung'**
  String get settingsPayment;

  /// Settings: Language
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get settingsLanguage;

  /// Settings: Theme
  ///
  /// In de, this message translates to:
  /// **'Design'**
  String get settingsTheme;

  /// Settings: Backup
  ///
  /// In de, this message translates to:
  /// **'Sicherung'**
  String get settingsBackup;

  /// Settings: Restaurant
  ///
  /// In de, this message translates to:
  /// **'Restaurant'**
  String get settingsRestaurant;

  /// Settings: Tax
  ///
  /// In de, this message translates to:
  /// **'Steuer (MWST)'**
  String get settingsTax;

  /// Settings: Receipt
  ///
  /// In de, this message translates to:
  /// **'Beleg'**
  String get settingsReceipt;

  /// Settings: Appearance
  ///
  /// In de, this message translates to:
  /// **'Erscheinungsbild'**
  String get settingsAppearance;

  /// Settings: About
  ///
  /// In de, this message translates to:
  /// **'Über'**
  String get settingsAbout;

  /// Settings: Demo Data
  ///
  /// In de, this message translates to:
  /// **'Demodaten'**
  String get settingsDemoData;

  /// Action: Save
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get actionSave;

  /// Action: Cancel
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get actionCancel;

  /// Action: Delete
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get actionDelete;

  /// Action: Edit
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get actionEdit;

  /// Action: Add
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get actionAdd;

  /// Action: Search
  ///
  /// In de, this message translates to:
  /// **'Suchen'**
  String get actionSearch;

  /// Action: Filter
  ///
  /// In de, this message translates to:
  /// **'Filtern'**
  String get actionFilter;

  /// Action: Confirm/OK
  ///
  /// In de, this message translates to:
  /// **'OK'**
  String get actionConfirm;

  /// Action: Close
  ///
  /// In de, this message translates to:
  /// **'Schliessen'**
  String get actionClose;

  /// Action: Back
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get actionBack;

  /// Action: Print
  ///
  /// In de, this message translates to:
  /// **'Drucken'**
  String get actionPrint;

  /// Action: Refresh
  ///
  /// In de, this message translates to:
  /// **'Aktualisieren'**
  String get actionRefresh;

  /// Status: Error
  ///
  /// In de, this message translates to:
  /// **'Fehler'**
  String get statusError;

  /// Status: Success
  ///
  /// In de, this message translates to:
  /// **'Erfolgreich'**
  String get statusSuccess;

  /// Status: Loading
  ///
  /// In de, this message translates to:
  /// **'Laden...'**
  String get statusLoading;

  /// Status: No data
  ///
  /// In de, this message translates to:
  /// **'Keine Daten'**
  String get statusNoData;

  /// Status: Offline
  ///
  /// In de, this message translates to:
  /// **'Offline'**
  String get statusOffline;

  /// Status: Online
  ///
  /// In de, this message translates to:
  /// **'Online'**
  String get statusOnline;

  /// Menu: Category
  ///
  /// In de, this message translates to:
  /// **'Kategorie'**
  String get menuCategory;

  /// Menu: Product
  ///
  /// In de, this message translates to:
  /// **'Produkt'**
  String get menuProduct;

  /// Menu: Price
  ///
  /// In de, this message translates to:
  /// **'Preis'**
  String get menuPrice;

  /// Menu: Modifier
  ///
  /// In de, this message translates to:
  /// **'Zusatz'**
  String get menuModifier;

  /// Menu: Active
  ///
  /// In de, this message translates to:
  /// **'Aktiv'**
  String get menuActive;

  /// Menu: Inactive
  ///
  /// In de, this message translates to:
  /// **'Inaktiv'**
  String get menuInactive;

  /// Orders: Order history
  ///
  /// In de, this message translates to:
  /// **'Bestellungshistorie'**
  String get orderHistory;

  /// Orders: Status
  ///
  /// In de, this message translates to:
  /// **'Status'**
  String get orderStatus;

  /// Orders: Open
  ///
  /// In de, this message translates to:
  /// **'Offen'**
  String get orderStatusOpen;

  /// Orders: Paid
  ///
  /// In de, this message translates to:
  /// **'Bezahlt'**
  String get orderStatusPaid;

  /// Orders: Cancelled
  ///
  /// In de, this message translates to:
  /// **'Storniert'**
  String get orderStatusCancelled;

  /// Orders: Refunded
  ///
  /// In de, this message translates to:
  /// **'Erstattet'**
  String get orderStatusRefunded;

  /// Dashboard: Daily revenue
  ///
  /// In de, this message translates to:
  /// **'Tagesumsatz'**
  String get dashboardDailyRevenue;

  /// Dashboard: Orders count
  ///
  /// In de, this message translates to:
  /// **'Bestellungen'**
  String get dashboardOrders;

  /// Dashboard: Average order
  ///
  /// In de, this message translates to:
  /// **'Ø Bestellung'**
  String get dashboardAvgOrder;

  /// Dashboard: Table occupancy
  ///
  /// In de, this message translates to:
  /// **'Tischauslastung'**
  String get dashboardTableOccupancy;

  /// Dashboard: Recent orders
  ///
  /// In de, this message translates to:
  /// **'Letzte Bestellungen'**
  String get dashboardRecentOrders;

  /// Dashboard: Hourly sales
  ///
  /// In de, this message translates to:
  /// **'Stündlicher Umsatz'**
  String get dashboardHourlySales;

  /// Floor plan
  ///
  /// In de, this message translates to:
  /// **'Saalplan'**
  String get floorPlan;

  /// Edit mode
  ///
  /// In de, this message translates to:
  /// **'Bearbeitungsmodus'**
  String get editMode;

  /// Confirm delete dialog title
  ///
  /// In de, this message translates to:
  /// **'Löschen bestätigen'**
  String get confirmDelete;

  /// Confirm delete dialog message
  ///
  /// In de, this message translates to:
  /// **'Möchten Sie diesen Eintrag wirklich löschen?'**
  String get confirmDeleteMessage;

  /// PIN login prompt
  ///
  /// In de, this message translates to:
  /// **'PIN eingeben'**
  String get pinLogin;

  /// Wrong PIN message
  ///
  /// In de, this message translates to:
  /// **'Falscher PIN'**
  String get pinWrong;

  /// Shift indicator: shift is open
  ///
  /// In de, this message translates to:
  /// **'Schicht offen'**
  String get shiftStatusOpen;

  /// Shift indicator: no active shift, tap to open
  ///
  /// In de, this message translates to:
  /// **'Keine Schicht – tippen zum Öffnen'**
  String get shiftNoShiftTapToOpen;

  /// Quick action: New Order
  ///
  /// In de, this message translates to:
  /// **'Neue Bestellung'**
  String get quickActionNewOrder;

  /// Quick action: Floor Plan
  ///
  /// In de, this message translates to:
  /// **'Saalplan'**
  String get quickActionFloorPlan;

  /// Quick action: Open Shift
  ///
  /// In de, this message translates to:
  /// **'Schicht öffnen'**
  String get quickActionOpenShift;

  /// Quick action: Close Shift
  ///
  /// In de, this message translates to:
  /// **'Schicht schliessen'**
  String get quickActionCloseShift;

  /// Quick action: Order History
  ///
  /// In de, this message translates to:
  /// **'Bestellungshistorie'**
  String get quickActionOrderHistory;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'fr', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
