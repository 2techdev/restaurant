// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'GastroCore Dashboard';

  @override
  String get login => 'Se connecter';

  @override
  String get logout => 'Se déconnecter';

  @override
  String get email => 'Adresse e-mail';

  @override
  String get password => 'Mot de passe';

  @override
  String get rememberMe => 'Se souvenir de moi';

  @override
  String get loginSubtitle => 'Accès pour les responsables de restaurant';

  @override
  String get loginError => 'E-mail ou mot de passe invalide';

  @override
  String get dashboard => 'Tableau de bord';

  @override
  String get orders => 'Commandes';

  @override
  String get menu => 'Carte';

  @override
  String get reports => 'Rapports';

  @override
  String get settings => 'Paramètres';

  @override
  String get totalRevenue => 'Chiffre d\'affaires aujourd\'hui';

  @override
  String get orderCount => 'Commandes';

  @override
  String get avgTicket => 'Ticket moyen';

  @override
  String get activeOrders => 'Commandes actives';

  @override
  String get tablesOccupied => 'Tables occupées';

  @override
  String get staffOnShift => 'Personnel en service';

  @override
  String get topItems => 'Articles les plus vendus';

  @override
  String get revenueChart => 'Évolution du chiffre d\'affaires';

  @override
  String get last7Days => '7 derniers jours';

  @override
  String get last30Days => '30 derniers jours';

  @override
  String get last90Days => '90 derniers jours';

  @override
  String get refresh => 'Actualiser';

  @override
  String get allOrders => 'Toutes les commandes';

  @override
  String get filterByDate => 'Filtrer par date';

  @override
  String get filterByStatus => 'Filtrer par statut';

  @override
  String get exportCsv => 'Exporter CSV';

  @override
  String orderNumber(String number) {
    return 'Commande #$number';
  }

  @override
  String get paid => 'Payé';

  @override
  String get open => 'Ouvert';

  @override
  String get preparing => 'En préparation';

  @override
  String get closed => 'Fermé';

  @override
  String get cancelled => 'Annulé';

  @override
  String get dineIn => 'Sur place';

  @override
  String get takeaway => 'À emporter';

  @override
  String get categories => 'Catégories';

  @override
  String get products => 'Produits';

  @override
  String get addProduct => 'Ajouter un produit';

  @override
  String get addCategory => 'Ajouter une catégorie';

  @override
  String get editProduct => 'Modifier le produit';

  @override
  String get available => 'Disponible';

  @override
  String get price => 'Prix';

  @override
  String get taxGroup => 'Groupe de TVA';

  @override
  String get dailyReport => 'Quotidien';

  @override
  String get weeklyReport => 'Hebdomadaire';

  @override
  String get monthlyReport => 'Mensuel';

  @override
  String get salesByCategory => 'Ventes par catégorie';

  @override
  String get paymentBreakdown => 'Modes de paiement';

  @override
  String get staffPerformance => 'Performance du personnel';

  @override
  String get mwstReport => 'Rapport TVA';

  @override
  String get restaurantInfo => 'Informations restaurant';

  @override
  String get printerConfig => 'Configuration imprimante';

  @override
  String get taxSettings => 'Paramètres TVA';

  @override
  String get userManagement => 'Gestion des utilisateurs';

  @override
  String get save => 'Enregistrer';

  @override
  String get cancel => 'Annuler';

  @override
  String get add => 'Ajouter';

  @override
  String get edit => 'Modifier';

  @override
  String get delete => 'Supprimer';

  @override
  String get from => 'De';

  @override
  String get to => 'À';

  @override
  String get apply => 'Appliquer';

  @override
  String get today => 'Aujourd\'hui';

  @override
  String get yesterday => 'Hier';

  @override
  String get thisWeek => 'Cette semaine';

  @override
  String get thisMonth => 'Ce mois';

  @override
  String get chf => 'CHF';

  @override
  String get loading => 'Chargement…';

  @override
  String get noData => 'Aucune donnée';

  @override
  String get error => 'Erreur';

  @override
  String get retry => 'Réessayer';

  @override
  String get darkMode => 'Mode sombre';

  @override
  String get lightMode => 'Mode clair';

  @override
  String get language => 'Langue';

  @override
  String get copiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get saveSuccess => 'Modifications enregistrées';
}
