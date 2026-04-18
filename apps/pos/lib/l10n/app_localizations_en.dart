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
  String gangLabel(int number) {
    return 'Gang $number';
  }

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

  @override
  String get navCustomers => 'Customers';

  @override
  String get crmTitle => 'Customer Management';

  @override
  String get crmNewCustomer => 'New Customer';

  @override
  String get crmEditCustomer => 'Edit Customer';

  @override
  String get crmDeleteCustomer => 'Delete Customer';

  @override
  String get crmName => 'Name';

  @override
  String get crmPhone => 'Phone';

  @override
  String get crmEmail => 'Email';

  @override
  String get crmAddress => 'Address';

  @override
  String get crmBirthday => 'Birthday';

  @override
  String get crmNotes => 'Notes';

  @override
  String get crmTotalOrders => 'Orders';

  @override
  String get crmTotalSpent => 'Revenue';

  @override
  String get crmLoyaltyPoints => 'Loyalty Points';

  @override
  String get crmTierBronze => 'Bronze';

  @override
  String get crmTierSilver => 'Silver';

  @override
  String get crmTierGold => 'Gold';

  @override
  String crmBirthdayReminder(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Birthdays',
      one: '1 Birthday',
    );
    return '$_temp0';
  }

  @override
  String get loyaltyTitle => 'Loyalty Points';

  @override
  String get loyaltyRedeem => 'Redeem Points';

  @override
  String get loyaltyAdjust => 'Adjust Points';

  @override
  String get loyaltyEarnRule => 'Spend CHF 1 = earn 1 point';

  @override
  String get loyaltyRedeemRule => '100 points = CHF 1.00 discount';

  @override
  String get loyaltyTransactionEarn => 'Points earned';

  @override
  String get loyaltyTransactionRedeem => 'Points redeemed';

  @override
  String get loyaltyTransactionAdjust => 'Manual adjustment';

  @override
  String get loyaltyTransactionExpire => 'Points expired';

  @override
  String get reservationNew => 'New Reservation';

  @override
  String get reservationEdit => 'Edit Reservation';

  @override
  String get reservationNoShow => 'No Show';

  @override
  String get reservationCancel => 'Cancel Reservation';

  @override
  String get reservationErrorTimeRange => 'End time must be after start time';

  @override
  String get reservationErrorConflict =>
      'This time slot conflicts with an existing reservation';

  @override
  String get reservationCustomerInfo => 'Customer Information';

  @override
  String get reservationCustomerName => 'Customer Name';

  @override
  String get reservationNameRequired => 'Name is required';

  @override
  String get reservationCustomerPhone => 'Phone Number';

  @override
  String get reservationCustomerEmail => 'Email Address';

  @override
  String courseLabel(String number) {
    String _temp0 = intl.Intl.selectLogic(number, {
      '1': 'Course 1',
      '2': 'Course 2',
      '3': 'Course 3',
      '4': 'Course 4',
      '5': 'Course 5',
      'other': 'Course $number',
    });
    return '$_temp0';
  }

  @override
  String get menuCategoryStarter => 'Starter';

  @override
  String get menuCategoryMain => 'Main';

  @override
  String get menuCategoryDessert => 'Dessert';

  @override
  String get posServiceCharge => 'Service';

  @override
  String get posCover => 'Cover';

  @override
  String get settingsLocale => 'Language & Region';

  @override
  String get fiscalReceiptVat => 'VAT';
}
