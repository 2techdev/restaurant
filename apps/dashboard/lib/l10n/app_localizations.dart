import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_tr.dart';

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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
    Locale('tr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In de, this message translates to:
  /// **'GastroCore Dashboard'**
  String get appTitle;

  /// No description provided for @login.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get login;

  /// No description provided for @logout.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get logout;

  /// No description provided for @email.
  ///
  /// In de, this message translates to:
  /// **'E-Mail-Adresse'**
  String get email;

  /// No description provided for @password.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get password;

  /// No description provided for @rememberMe.
  ///
  /// In de, this message translates to:
  /// **'Angemeldet bleiben'**
  String get rememberMe;

  /// No description provided for @loginSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Zugang für Restaurant-Manager'**
  String get loginSubtitle;

  /// No description provided for @loginError.
  ///
  /// In de, this message translates to:
  /// **'Ungültige E-Mail oder Passwort'**
  String get loginError;

  /// No description provided for @dashboard.
  ///
  /// In de, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @orders.
  ///
  /// In de, this message translates to:
  /// **'Bestellungen'**
  String get orders;

  /// No description provided for @menu.
  ///
  /// In de, this message translates to:
  /// **'Speisekarte'**
  String get menu;

  /// No description provided for @reports.
  ///
  /// In de, this message translates to:
  /// **'Berichte'**
  String get reports;

  /// No description provided for @settings.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get settings;

  /// No description provided for @totalRevenue.
  ///
  /// In de, this message translates to:
  /// **'Umsatz heute'**
  String get totalRevenue;

  /// No description provided for @orderCount.
  ///
  /// In de, this message translates to:
  /// **'Bestellungen'**
  String get orderCount;

  /// No description provided for @avgTicket.
  ///
  /// In de, this message translates to:
  /// **'Ø Bon'**
  String get avgTicket;

  /// No description provided for @activeOrders.
  ///
  /// In de, this message translates to:
  /// **'Aktive Bestellungen'**
  String get activeOrders;

  /// No description provided for @tablesOccupied.
  ///
  /// In de, this message translates to:
  /// **'Besetzte Tische'**
  String get tablesOccupied;

  /// No description provided for @staffOnShift.
  ///
  /// In de, this message translates to:
  /// **'Personal in Schicht'**
  String get staffOnShift;

  /// No description provided for @topItems.
  ///
  /// In de, this message translates to:
  /// **'Top Artikel heute'**
  String get topItems;

  /// No description provided for @revenueChart.
  ///
  /// In de, this message translates to:
  /// **'Umsatzverlauf'**
  String get revenueChart;

  /// No description provided for @last7Days.
  ///
  /// In de, this message translates to:
  /// **'Letzte 7 Tage'**
  String get last7Days;

  /// No description provided for @last30Days.
  ///
  /// In de, this message translates to:
  /// **'Letzte 30 Tage'**
  String get last30Days;

  /// No description provided for @last90Days.
  ///
  /// In de, this message translates to:
  /// **'Letzte 90 Tage'**
  String get last90Days;

  /// No description provided for @refresh.
  ///
  /// In de, this message translates to:
  /// **'Aktualisieren'**
  String get refresh;

  /// No description provided for @allOrders.
  ///
  /// In de, this message translates to:
  /// **'Alle Bestellungen'**
  String get allOrders;

  /// No description provided for @filterByDate.
  ///
  /// In de, this message translates to:
  /// **'Nach Datum filtern'**
  String get filterByDate;

  /// No description provided for @filterByStatus.
  ///
  /// In de, this message translates to:
  /// **'Nach Status filtern'**
  String get filterByStatus;

  /// No description provided for @exportCsv.
  ///
  /// In de, this message translates to:
  /// **'CSV Export'**
  String get exportCsv;

  /// No description provided for @orderNumber.
  ///
  /// In de, this message translates to:
  /// **'Bestellung #{number}'**
  String orderNumber(String number);

  /// No description provided for @paid.
  ///
  /// In de, this message translates to:
  /// **'Bezahlt'**
  String get paid;

  /// No description provided for @open.
  ///
  /// In de, this message translates to:
  /// **'Offen'**
  String get open;

  /// No description provided for @preparing.
  ///
  /// In de, this message translates to:
  /// **'In Zubereitung'**
  String get preparing;

  /// No description provided for @closed.
  ///
  /// In de, this message translates to:
  /// **'Geschlossen'**
  String get closed;

  /// No description provided for @cancelled.
  ///
  /// In de, this message translates to:
  /// **'Storniert'**
  String get cancelled;

  /// No description provided for @dineIn.
  ///
  /// In de, this message translates to:
  /// **'Im Restaurant'**
  String get dineIn;

  /// No description provided for @takeaway.
  ///
  /// In de, this message translates to:
  /// **'Takeaway'**
  String get takeaway;

  /// No description provided for @categories.
  ///
  /// In de, this message translates to:
  /// **'Kategorien'**
  String get categories;

  /// No description provided for @products.
  ///
  /// In de, this message translates to:
  /// **'Produkte'**
  String get products;

  /// No description provided for @addProduct.
  ///
  /// In de, this message translates to:
  /// **'Produkt hinzufügen'**
  String get addProduct;

  /// No description provided for @addCategory.
  ///
  /// In de, this message translates to:
  /// **'Kategorie hinzufügen'**
  String get addCategory;

  /// No description provided for @editProduct.
  ///
  /// In de, this message translates to:
  /// **'Produkt bearbeiten'**
  String get editProduct;

  /// No description provided for @available.
  ///
  /// In de, this message translates to:
  /// **'Verfügbar'**
  String get available;

  /// No description provided for @price.
  ///
  /// In de, this message translates to:
  /// **'Preis'**
  String get price;

  /// No description provided for @taxGroup.
  ///
  /// In de, this message translates to:
  /// **'Steuergruppe'**
  String get taxGroup;

  /// No description provided for @dailyReport.
  ///
  /// In de, this message translates to:
  /// **'Täglich'**
  String get dailyReport;

  /// No description provided for @weeklyReport.
  ///
  /// In de, this message translates to:
  /// **'Wöchentlich'**
  String get weeklyReport;

  /// No description provided for @monthlyReport.
  ///
  /// In de, this message translates to:
  /// **'Monatlich'**
  String get monthlyReport;

  /// No description provided for @salesByCategory.
  ///
  /// In de, this message translates to:
  /// **'Umsatz nach Kategorie'**
  String get salesByCategory;

  /// No description provided for @paymentBreakdown.
  ///
  /// In de, this message translates to:
  /// **'Zahlungsmethoden'**
  String get paymentBreakdown;

  /// No description provided for @staffPerformance.
  ///
  /// In de, this message translates to:
  /// **'Personalleistung'**
  String get staffPerformance;

  /// No description provided for @mwstReport.
  ///
  /// In de, this message translates to:
  /// **'MWST-Abrechnung'**
  String get mwstReport;

  /// No description provided for @restaurantInfo.
  ///
  /// In de, this message translates to:
  /// **'Restaurant-Informationen'**
  String get restaurantInfo;

  /// No description provided for @printerConfig.
  ///
  /// In de, this message translates to:
  /// **'Druckereinstellungen'**
  String get printerConfig;

  /// No description provided for @taxSettings.
  ///
  /// In de, this message translates to:
  /// **'Steuereinstellungen'**
  String get taxSettings;

  /// No description provided for @userManagement.
  ///
  /// In de, this message translates to:
  /// **'Benutzerverwaltung'**
  String get userManagement;

  /// No description provided for @save.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get cancel;

  /// No description provided for @add.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get add;

  /// No description provided for @edit.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get delete;

  /// No description provided for @from.
  ///
  /// In de, this message translates to:
  /// **'Von'**
  String get from;

  /// No description provided for @to.
  ///
  /// In de, this message translates to:
  /// **'Bis'**
  String get to;

  /// No description provided for @apply.
  ///
  /// In de, this message translates to:
  /// **'Anwenden'**
  String get apply;

  /// No description provided for @today.
  ///
  /// In de, this message translates to:
  /// **'Heute'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In de, this message translates to:
  /// **'Gestern'**
  String get yesterday;

  /// No description provided for @thisWeek.
  ///
  /// In de, this message translates to:
  /// **'Diese Woche'**
  String get thisWeek;

  /// No description provided for @thisMonth.
  ///
  /// In de, this message translates to:
  /// **'Dieser Monat'**
  String get thisMonth;

  /// No description provided for @chf.
  ///
  /// In de, this message translates to:
  /// **'CHF'**
  String get chf;

  /// No description provided for @loading.
  ///
  /// In de, this message translates to:
  /// **'Laden…'**
  String get loading;

  /// No description provided for @noData.
  ///
  /// In de, this message translates to:
  /// **'Keine Daten'**
  String get noData;

  /// No description provided for @error.
  ///
  /// In de, this message translates to:
  /// **'Fehler'**
  String get error;

  /// No description provided for @retry.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get retry;

  /// No description provided for @darkMode.
  ///
  /// In de, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In de, this message translates to:
  /// **'Light Mode'**
  String get lightMode;

  /// No description provided for @language.
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get language;

  /// No description provided for @copiedToClipboard.
  ///
  /// In de, this message translates to:
  /// **'In Zwischenablage kopiert'**
  String get copiedToClipboard;

  /// No description provided for @saveSuccess.
  ///
  /// In de, this message translates to:
  /// **'Änderungen gespeichert'**
  String get saveSuccess;
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
      <String>['de', 'en', 'fr', 'it', 'tr'].contains(locale.languageCode);

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
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
