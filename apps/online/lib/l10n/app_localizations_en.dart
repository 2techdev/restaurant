// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Order Online';

  @override
  String get viewMenu => 'View Menu';

  @override
  String get search => 'Search';

  @override
  String get searchPlaceholder => 'Search dishes…';

  @override
  String get allCategories => 'All';

  @override
  String get addToCart => 'Add to Cart';

  @override
  String get cart => 'Cart';

  @override
  String get cartEmpty => 'Your cart is empty';

  @override
  String get cartEmptyHint => 'Browse the menu and add items';

  @override
  String get browseMenu => 'Browse Menu';

  @override
  String get quantity => 'Quantity';

  @override
  String get notes => 'Special requests';

  @override
  String get notesPlaceholder => 'Allergies, preferences…';

  @override
  String get orderType => 'Order type';

  @override
  String get dineIn => 'Dine-in';

  @override
  String get takeaway => 'Takeaway';

  @override
  String get tableNumber => 'Table number';

  @override
  String get tableNumberHint => 'Enter your table number';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get vat => 'MWST / TVA / IVA';

  @override
  String vatRate(String rate) {
    return 'VAT $rate%';
  }

  @override
  String get total => 'Total';

  @override
  String get rounding => 'Rounding';

  @override
  String get placeOrder => 'Place Order';

  @override
  String get orderSummary => 'Order Summary';

  @override
  String get yourName => 'Your name (optional)';

  @override
  String get yourNameHint => 'e.g. Maria';

  @override
  String get orderNotes => 'Order notes';

  @override
  String get orderNotesHint => 'Any notes for the kitchen';

  @override
  String get confirmOrder => 'Confirm Order';

  @override
  String get orderPlaced => 'Order placed!';

  @override
  String orderNumber(String number) {
    return 'Order #$number';
  }

  @override
  String estimatedWait(String minutes) {
    return 'Estimated wait: $minutes min';
  }

  @override
  String get orderSentToKitchen => 'Your order has been sent to the kitchen.';

  @override
  String get trackOrder => 'Track Order';

  @override
  String get orderStatus => 'Order Status';

  @override
  String get statusReceived => 'Order received';

  @override
  String get statusPreparing => 'Preparing';

  @override
  String get statusReady => 'Ready!';

  @override
  String get statusServed => 'Served';

  @override
  String get backToMenu => 'Back to Menu';

  @override
  String get remove => 'Remove';

  @override
  String get edit => 'Edit';

  @override
  String get close => 'Close';

  @override
  String get language => 'Language';

  @override
  String get required => 'Required';

  @override
  String get optional => 'Optional';

  @override
  String get outOfStock => 'Unavailable';

  @override
  String get customize => 'Customize';

  @override
  String get chooseOne => 'Choose one';

  @override
  String chooseUpTo(String max) {
    return 'Choose up to $max';
  }

  @override
  String chooseAtLeast(String min) {
    return 'Choose at least $min';
  }

  @override
  String get free => 'Free';

  @override
  String get itemAdded => 'Added to cart';

  @override
  String get errorLoadingMenu => 'Could not load menu. Please try again.';

  @override
  String get retry => 'Retry';

  @override
  String get orderFailed => 'Could not place order. Please try again.';

  @override
  String get loading => 'Loading…';

  @override
  String get chf => 'CHF';

  @override
  String get modifiers => 'Customizations';

  @override
  String tableAutoFilled(String number) {
    return 'Table $number auto-filled from QR code';
  }

  @override
  String get selectTableNumber => 'Please enter your table number';

  @override
  String get continueToCheckout => 'Continue to Checkout';

  @override
  String get orderTypeRequired => 'Please select dine-in or takeaway';

  @override
  String itemsInCart(String count) {
    return '$count item(s) in cart';
  }
}
