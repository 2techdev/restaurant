// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'GastroCore POS';

  @override
  String get navHome => 'Home';

  @override
  String get navOrders => 'Orders';

  @override
  String get navTables => 'Tables';

  @override
  String get navMenu => 'Menu';

  @override
  String get navShift => 'Shift';

  @override
  String get navSettings => 'Settings';

  @override
  String get navReports => 'Reports';

  @override
  String get navKitchen => 'Kitchen';

  @override
  String get posNewOrder => 'New Order';

  @override
  String get posOrder => 'Order';

  @override
  String get posPayment => 'Payment';

  @override
  String get posCash => 'Cash';

  @override
  String get posCard => 'Card';

  @override
  String get posTwint => 'TWINT';

  @override
  String get posTotal => 'Total';

  @override
  String get posSubtotal => 'Subtotal';

  @override
  String get posVat => 'VAT';

  @override
  String get posDiscount => 'Discount';

  @override
  String get posCancel => 'Cancel';

  @override
  String get posRefund => 'Refund';

  @override
  String get posCharge => 'Charge';

  @override
  String get posGiven => 'Amount given';

  @override
  String get posChange => 'Change';

  @override
  String get posSplitBill => 'Split Bill';

  @override
  String get posOrderType => 'Order type';

  @override
  String get posDineIn => 'Dine in';

  @override
  String get posTakeaway => 'Takeaway';

  @override
  String get posDelivery => 'Delivery';

  @override
  String get tableEmpty => 'Free';

  @override
  String get tableOccupied => 'Occupied';

  @override
  String get tableReserved => 'Reserved';

  @override
  String get tableDirty => 'Dirty';

  @override
  String get tableMerge => 'Merge';

  @override
  String get tableTransfer => 'Transfer';

  @override
  String tableGuest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count guests',
      one: '1 guest',
    );
    return '$_temp0';
  }

  @override
  String get tableNewTable => 'New Table';

  @override
  String get tableFloor => 'Zone';

  @override
  String get tableCapacity => 'Capacity';

  @override
  String get shiftOpen => 'Open';

  @override
  String get shiftClose => 'Close';

  @override
  String get shiftCashCount => 'Cash Count';

  @override
  String get shiftDifference => 'Difference';

  @override
  String get shiftZReport => 'Z-Report';

  @override
  String get shiftXReport => 'X-Report (Interim)';

  @override
  String get shiftOpenShift => 'Open Shift';

  @override
  String get shiftCloseShift => 'Close Shift';

  @override
  String get shiftOpeningFloat => 'Opening Float';

  @override
  String get shiftCashIn => 'Cash In';

  @override
  String get shiftCashOut => 'Cash Out';

  @override
  String get shiftNoActiveShift => 'No Active Shift';

  @override
  String get shiftOpenCashDrawer => 'Open Cash Drawer';

  @override
  String get receiptNo => 'Receipt No.';

  @override
  String get receiptDate => 'Date';

  @override
  String get receiptTime => 'Time';

  @override
  String get receiptCashier => 'Cashier';

  @override
  String get receiptThankYou => 'Thank you!';

  @override
  String get receiptTable => 'Table';

  @override
  String get settingsPrinter => 'Printer';

  @override
  String get settingsPayment => 'Payment';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsBackup => 'Backup';

  @override
  String get settingsRestaurant => 'Restaurant';

  @override
  String get settingsTax => 'Tax (VAT)';

  @override
  String get settingsReceipt => 'Receipt';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsDemoData => 'Demo Data';

  @override
  String get actionSave => 'Save';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionSearch => 'Search';

  @override
  String get actionFilter => 'Filter';

  @override
  String get actionConfirm => 'OK';

  @override
  String get actionClose => 'Close';

  @override
  String get actionBack => 'Back';

  @override
  String get actionPrint => 'Print';

  @override
  String get actionRefresh => 'Refresh';

  @override
  String get statusError => 'Error';

  @override
  String get statusSuccess => 'Success';

  @override
  String get statusLoading => 'Loading...';

  @override
  String get statusNoData => 'No data';

  @override
  String get statusOffline => 'Offline';

  @override
  String get statusOnline => 'Online';

  @override
  String get menuCategory => 'Category';

  @override
  String get menuProduct => 'Product';

  @override
  String get menuPrice => 'Price';

  @override
  String get menuModifier => 'Modifier';

  @override
  String get menuActive => 'Active';

  @override
  String get menuInactive => 'Inactive';

  @override
  String get orderHistory => 'Order History';

  @override
  String get orderStatus => 'Status';

  @override
  String get orderStatusOpen => 'Open';

  @override
  String get orderStatusPaid => 'Paid';

  @override
  String get orderStatusCancelled => 'Cancelled';

  @override
  String get orderStatusRefunded => 'Refunded';

  @override
  String get dashboardDailyRevenue => 'Daily Revenue';

  @override
  String get dashboardOrders => 'Orders';

  @override
  String get dashboardAvgOrder => 'Avg. Order';

  @override
  String get dashboardTableOccupancy => 'Table Occupancy';

  @override
  String get dashboardRecentOrders => 'Recent Orders';

  @override
  String get dashboardHourlySales => 'Hourly Sales';

  @override
  String get floorPlan => 'Floor Plan';

  @override
  String get editMode => 'Edit Mode';

  @override
  String get confirmDelete => 'Confirm Delete';

  @override
  String get confirmDeleteMessage =>
      'Are you sure you want to delete this item?';

  @override
  String get pinLogin => 'Enter PIN';

  @override
  String get pinWrong => 'Wrong PIN';

  @override
  String get shiftStatusOpen => 'Shift Open';

  @override
  String get shiftNoShiftTapToOpen => 'No Shift — Tap to Open';

  @override
  String get quickActionNewOrder => 'New Order';

  @override
  String get quickActionFloorPlan => 'Floor Plan';

  @override
  String get quickActionOpenShift => 'Open Shift';

  @override
  String get quickActionCloseShift => 'Close Shift';

  @override
  String get quickActionOrderHistory => 'Order History';
}
