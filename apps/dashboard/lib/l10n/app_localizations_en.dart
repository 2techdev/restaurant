// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'GastroCore Dashboard';

  @override
  String get login => 'Sign In';

  @override
  String get logout => 'Sign Out';

  @override
  String get email => 'Email Address';

  @override
  String get password => 'Password';

  @override
  String get rememberMe => 'Remember me';

  @override
  String get loginSubtitle => 'Access for restaurant managers';

  @override
  String get loginError => 'Invalid email or password';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get orders => 'Orders';

  @override
  String get menu => 'Menu';

  @override
  String get reports => 'Reports';

  @override
  String get settings => 'Settings';

  @override
  String get totalRevenue => 'Today\'s Revenue';

  @override
  String get orderCount => 'Orders';

  @override
  String get avgTicket => 'Avg. Ticket';

  @override
  String get activeOrders => 'Active Orders';

  @override
  String get tablesOccupied => 'Tables Occupied';

  @override
  String get staffOnShift => 'Staff on Shift';

  @override
  String get topItems => 'Top Items Today';

  @override
  String get revenueChart => 'Revenue Trend';

  @override
  String get last7Days => 'Last 7 Days';

  @override
  String get last30Days => 'Last 30 Days';

  @override
  String get last90Days => 'Last 90 Days';

  @override
  String get refresh => 'Refresh';

  @override
  String get allOrders => 'All Orders';

  @override
  String get filterByDate => 'Filter by Date';

  @override
  String get filterByStatus => 'Filter by Status';

  @override
  String get exportCsv => 'Export CSV';

  @override
  String orderNumber(String number) {
    return 'Order #$number';
  }

  @override
  String get paid => 'Paid';

  @override
  String get open => 'Open';

  @override
  String get preparing => 'Preparing';

  @override
  String get closed => 'Closed';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get dineIn => 'Dine In';

  @override
  String get takeaway => 'Takeaway';

  @override
  String get categories => 'Categories';

  @override
  String get products => 'Products';

  @override
  String get addProduct => 'Add Product';

  @override
  String get addCategory => 'Add Category';

  @override
  String get editProduct => 'Edit Product';

  @override
  String get available => 'Available';

  @override
  String get price => 'Price';

  @override
  String get taxGroup => 'Tax Group';

  @override
  String get dailyReport => 'Daily';

  @override
  String get weeklyReport => 'Weekly';

  @override
  String get monthlyReport => 'Monthly';

  @override
  String get salesByCategory => 'Sales by Category';

  @override
  String get paymentBreakdown => 'Payment Methods';

  @override
  String get staffPerformance => 'Staff Performance';

  @override
  String get mwstReport => 'VAT Report';

  @override
  String get restaurantInfo => 'Restaurant Info';

  @override
  String get printerConfig => 'Printer Settings';

  @override
  String get taxSettings => 'Tax Settings';

  @override
  String get userManagement => 'User Management';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get add => 'Add';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get from => 'From';

  @override
  String get to => 'To';

  @override
  String get apply => 'Apply';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get thisWeek => 'This Week';

  @override
  String get thisMonth => 'This Month';

  @override
  String get chf => 'CHF';

  @override
  String get loading => 'Loading…';

  @override
  String get noData => 'No data';

  @override
  String get error => 'Error';

  @override
  String get retry => 'Try Again';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get lightMode => 'Light Mode';

  @override
  String get language => 'Language';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get saveSuccess => 'Changes saved';
}
