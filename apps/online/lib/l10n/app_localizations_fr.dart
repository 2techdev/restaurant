// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Commander en ligne';

  @override
  String get viewMenu => 'Voir le menu';

  @override
  String get search => 'Rechercher';

  @override
  String get searchPlaceholder => 'Rechercher des plats…';

  @override
  String get allCategories => 'Tout';

  @override
  String get addToCart => 'Ajouter au panier';

  @override
  String get cart => 'Panier';

  @override
  String get cartEmpty => 'Votre panier est vide';

  @override
  String get cartEmptyHint => 'Parcourez le menu et ajoutez des articles';

  @override
  String get browseMenu => 'Menu';

  @override
  String get quantity => 'Quantité';

  @override
  String get notes => 'Demandes spéciales';

  @override
  String get notesPlaceholder => 'Allergies, préférences…';

  @override
  String get orderType => 'Type de commande';

  @override
  String get dineIn => 'Sur place';

  @override
  String get takeaway => 'À emporter';

  @override
  String get tableNumber => 'Numéro de table';

  @override
  String get tableNumberHint => 'Entrez votre numéro de table';

  @override
  String get subtotal => 'Sous-total';

  @override
  String get vat => 'TVA';

  @override
  String vatRate(String rate) {
    return 'TVA $rate%';
  }

  @override
  String get total => 'Total';

  @override
  String get rounding => 'Arrondi';

  @override
  String get placeOrder => 'Passer la commande';

  @override
  String get orderSummary => 'Résumé de la commande';

  @override
  String get yourName => 'Votre nom (optionnel)';

  @override
  String get yourNameHint => 'ex. Maria';

  @override
  String get orderNotes => 'Notes de commande';

  @override
  String get orderNotesHint => 'Remarques pour la cuisine';

  @override
  String get confirmOrder => 'Confirmer la commande';

  @override
  String get orderPlaced => 'Commande passée!';

  @override
  String orderNumber(String number) {
    return 'Commande #$number';
  }

  @override
  String estimatedWait(String minutes) {
    return 'Attente estimée: $minutes min';
  }

  @override
  String get orderSentToKitchen => 'Votre commande a été envoyée en cuisine.';

  @override
  String get trackOrder => 'Suivre la commande';

  @override
  String get orderStatus => 'Statut de la commande';

  @override
  String get statusReceived => 'Commande reçue';

  @override
  String get statusPreparing => 'En préparation';

  @override
  String get statusReady => 'Prête!';

  @override
  String get statusServed => 'Servie';

  @override
  String get backToMenu => 'Retour au menu';

  @override
  String get remove => 'Supprimer';

  @override
  String get edit => 'Modifier';

  @override
  String get close => 'Fermer';

  @override
  String get language => 'Langue';

  @override
  String get required => 'Obligatoire';

  @override
  String get optional => 'Optionnel';

  @override
  String get outOfStock => 'Indisponible';

  @override
  String get customize => 'Personnaliser';

  @override
  String get chooseOne => 'Choisir une option';

  @override
  String chooseUpTo(String max) {
    return 'Choisir jusqu\'à $max';
  }

  @override
  String chooseAtLeast(String min) {
    return 'Choisir au moins $min';
  }

  @override
  String get free => 'Gratuit';

  @override
  String get itemAdded => 'Ajouté au panier';

  @override
  String get errorLoadingMenu =>
      'Impossible de charger le menu. Veuillez réessayer.';

  @override
  String get retry => 'Réessayer';

  @override
  String get orderFailed => 'Commande échouée. Veuillez réessayer.';

  @override
  String get loading => 'Chargement…';

  @override
  String get chf => 'CHF';

  @override
  String get modifiers => 'Personnalisations';

  @override
  String tableAutoFilled(String number) {
    return 'Table $number détectée via QR';
  }

  @override
  String get selectTableNumber => 'Veuillez entrer votre numéro de table';

  @override
  String get continueToCheckout => 'Passer à la caisse';

  @override
  String get orderTypeRequired => 'Veuillez choisir sur place ou à emporter';

  @override
  String itemsInCart(String count) {
    return '$count article(s) dans le panier';
  }
}
