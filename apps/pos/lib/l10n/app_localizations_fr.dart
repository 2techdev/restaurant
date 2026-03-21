// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'GastroCore POS';

  @override
  String get navHome => 'Accueil';

  @override
  String get navOrders => 'Commandes';

  @override
  String get navTables => 'Tables';

  @override
  String get navMenu => 'Menu';

  @override
  String get navShift => 'Service';

  @override
  String get navSettings => 'Paramètres';

  @override
  String get navReports => 'Rapports';

  @override
  String get navKitchen => 'Cuisine';

  @override
  String get posNewOrder => 'Nouvelle commande';

  @override
  String get posOrder => 'Commande';

  @override
  String get posPayment => 'Paiement';

  @override
  String get posCash => 'Espèces';

  @override
  String get posCard => 'Carte';

  @override
  String get posTwint => 'TWINT';

  @override
  String get posTotal => 'Total';

  @override
  String get posSubtotal => 'Sous-total';

  @override
  String get posVat => 'TVA';

  @override
  String get posDiscount => 'Remise';

  @override
  String get posCancel => 'Annuler';

  @override
  String get posRefund => 'Remboursement';

  @override
  String get posCharge => 'Encaisser';

  @override
  String get posGiven => 'Montant donné';

  @override
  String get posChange => 'Monnaie';

  @override
  String get posSplitBill => 'Partager l\'addition';

  @override
  String get posOrderType => 'Type de commande';

  @override
  String get posDineIn => 'Sur place';

  @override
  String get posTakeaway => 'À emporter';

  @override
  String get posDelivery => 'Livraison';

  @override
  String get tableEmpty => 'Libre';

  @override
  String get tableOccupied => 'Occupée';

  @override
  String get tableReserved => 'Réservée';

  @override
  String get tableDirty => 'Sale';

  @override
  String get tableMerge => 'Fusionner';

  @override
  String get tableTransfer => 'Transférer';

  @override
  String tableGuest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count couverts',
      one: '1 couvert',
    );
    return '$_temp0';
  }

  @override
  String get tableNewTable => 'Nouvelle table';

  @override
  String get tableFloor => 'Zone';

  @override
  String get tableCapacity => 'Capacité';

  @override
  String get shiftOpen => 'Ouvrir';

  @override
  String get shiftClose => 'Fermer';

  @override
  String get shiftCashCount => 'Comptage caisse';

  @override
  String get shiftDifference => 'Différence';

  @override
  String get shiftZReport => 'Rapport Z';

  @override
  String get shiftXReport => 'Rapport X (intermédiaire)';

  @override
  String get shiftOpenShift => 'Ouvrir le service';

  @override
  String get shiftCloseShift => 'Fermer le service';

  @override
  String get shiftOpeningFloat => 'Fond de caisse';

  @override
  String get shiftCashIn => 'Entrée caisse';

  @override
  String get shiftCashOut => 'Sortie caisse';

  @override
  String get shiftNoActiveShift => 'Aucun service actif';

  @override
  String get shiftOpenCashDrawer => 'Ouvrir le tiroir-caisse';

  @override
  String get receiptNo => 'N° reçu';

  @override
  String get receiptDate => 'Date';

  @override
  String get receiptTime => 'Heure';

  @override
  String get receiptCashier => 'Caissier';

  @override
  String get receiptThankYou => 'Merci beaucoup!';

  @override
  String get receiptTable => 'Table';

  @override
  String get settingsPrinter => 'Imprimante';

  @override
  String get settingsPayment => 'Paiement';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsTheme => 'Thème';

  @override
  String get settingsBackup => 'Sauvegarde';

  @override
  String get settingsRestaurant => 'Restaurant';

  @override
  String get settingsTax => 'Taxe (TVA)';

  @override
  String get settingsReceipt => 'Reçu';

  @override
  String get settingsAppearance => 'Apparence';

  @override
  String get settingsAbout => 'À propos';

  @override
  String get settingsDemoData => 'Données démo';

  @override
  String get actionSave => 'Enregistrer';

  @override
  String get actionCancel => 'Annuler';

  @override
  String get actionDelete => 'Supprimer';

  @override
  String get actionEdit => 'Modifier';

  @override
  String get actionAdd => 'Ajouter';

  @override
  String get actionSearch => 'Rechercher';

  @override
  String get actionFilter => 'Filtrer';

  @override
  String get actionConfirm => 'OK';

  @override
  String get actionClose => 'Fermer';

  @override
  String get actionBack => 'Retour';

  @override
  String get actionPrint => 'Imprimer';

  @override
  String get actionRefresh => 'Actualiser';

  @override
  String get statusError => 'Erreur';

  @override
  String get statusSuccess => 'Réussi';

  @override
  String get statusLoading => 'Chargement...';

  @override
  String get statusNoData => 'Aucune donnée';

  @override
  String get statusOffline => 'Hors ligne';

  @override
  String get statusOnline => 'En ligne';

  @override
  String get menuCategory => 'Catégorie';

  @override
  String get menuProduct => 'Produit';

  @override
  String get menuPrice => 'Prix';

  @override
  String get menuModifier => 'Option';

  @override
  String get menuActive => 'Actif';

  @override
  String get menuInactive => 'Inactif';

  @override
  String get orderHistory => 'Historique des commandes';

  @override
  String get orderStatus => 'Statut';

  @override
  String get orderStatusOpen => 'Ouvert';

  @override
  String get orderStatusPaid => 'Payé';

  @override
  String get orderStatusCancelled => 'Annulé';

  @override
  String get orderStatusRefunded => 'Remboursé';

  @override
  String get dashboardDailyRevenue => 'Chiffre d\'affaires';

  @override
  String get dashboardOrders => 'Commandes';

  @override
  String get dashboardAvgOrder => 'Commande moy.';

  @override
  String get dashboardTableOccupancy => 'Taux d\'occupation';

  @override
  String get dashboardRecentOrders => 'Dernières commandes';

  @override
  String get dashboardHourlySales => 'Ventes par heure';

  @override
  String get floorPlan => 'Plan de salle';

  @override
  String get editMode => 'Mode édition';

  @override
  String get confirmDelete => 'Confirmer la suppression';

  @override
  String get confirmDeleteMessage =>
      'Voulez-vous vraiment supprimer cet élément?';

  @override
  String get pinLogin => 'Entrer le PIN';

  @override
  String get pinWrong => 'PIN incorrect';

  @override
  String get shiftStatusOpen => 'Service en cours';

  @override
  String get shiftNoShiftTapToOpen => 'Aucun service – toucher pour ouvrir';

  @override
  String get quickActionNewOrder => 'Nouvelle commande';

  @override
  String get quickActionFloorPlan => 'Plan de salle';

  @override
  String get quickActionOpenShift => 'Ouvrir le service';

  @override
  String get quickActionCloseShift => 'Fermer le service';

  @override
  String get quickActionOrderHistory => 'Historique des commandes';

  @override
  String get navReservations => 'Réservations';

  @override
  String get reservationList => 'Réservations';

  @override
  String get reservationCalendar => 'Calendrier';

  @override
  String get reservationNew => 'Nouvelle réservation';

  @override
  String get reservationEdit => 'Modifier la réservation';

  @override
  String get reservationToday => 'Aujourd\'hui';

  @override
  String get reservationNoUpcoming => 'Aucune réservation à venir';

  @override
  String get reservationNoReservations => 'Aucune réservation pour ce jour';

  @override
  String get reservationCustomerInfo => 'Informations du client';

  @override
  String get reservationCustomerName => 'Nom du client';

  @override
  String get reservationCustomerPhone => 'Téléphone';

  @override
  String get reservationCustomerEmail => 'E-mail';

  @override
  String get reservationDateTime => 'Date et heure';

  @override
  String get reservationDate => 'Date';

  @override
  String get reservationTime => 'Heure';

  @override
  String get reservationPartySize => 'Nombre de personnes';

  @override
  String get reservationTable => 'Table';

  @override
  String get reservationTableOptional => 'Table (facultatif)';

  @override
  String get reservationNoTable => 'Aucune table assignée';

  @override
  String get reservationNotes => 'Remarques';

  @override
  String get reservationMeta => 'Infos de réservation';

  @override
  String get reservationChannel => 'Source';

  @override
  String get reservationStatus => 'Statut';

  @override
  String get reservationChangeStatus => 'Changer le statut';

  @override
  String get reservationChangeEndTime => 'Modifier l\'heure de fin';

  @override
  String get reservationChannelWalkIn => 'Sans réservation';

  @override
  String get reservationChannelOnline => 'En ligne';

  @override
  String get reservationChannelPhone => 'Téléphone';

  @override
  String get reservationStatusPending => 'En attente';

  @override
  String get reservationStatusConfirmed => 'Confirmé';

  @override
  String get reservationStatusSeated => 'Installé';

  @override
  String get reservationStatusCancelled => 'Annulé';

  @override
  String get reservationStatusNoShow => 'No-show';

  @override
  String get reservationConfirm => 'Confirmer';

  @override
  String get reservationSeat => 'Installer les clients';

  @override
  String get reservationNoShow => 'No-show';

  @override
  String get reservationCancel => 'Annuler la réservation';

  @override
  String get reservationViewDay => 'Jour';

  @override
  String get reservationViewWeek => 'Semaine';

  @override
  String get reservationNameRequired => 'Le nom du client est obligatoire';

  @override
  String get reservationErrorTimeRange =>
      'L\'heure de fin doit être après l\'heure de début';

  @override
  String get reservationErrorConflict =>
      'Cette table est déjà réservée à ce créneau';
}
