// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appTitle => 'Online Sipariş';

  @override
  String get viewMenu => 'Menüyü Gör';

  @override
  String get search => 'Ara';

  @override
  String get searchPlaceholder => 'Yemek ara…';

  @override
  String get allCategories => 'Tümü';

  @override
  String get addToCart => 'Sepete Ekle';

  @override
  String get cart => 'Sepet';

  @override
  String get cartEmpty => 'Sepetiniz boş';

  @override
  String get cartEmptyHint => 'Menüye göz atın ve ürün ekleyin';

  @override
  String get browseMenu => 'Menüye Göz At';

  @override
  String get quantity => 'Adet';

  @override
  String get notes => 'Özel istekler';

  @override
  String get notesPlaceholder => 'Alerjiler, tercihler…';

  @override
  String get orderType => 'Sipariş tipi';

  @override
  String get dineIn => 'Masada';

  @override
  String get takeaway => 'Paket';

  @override
  String get tableNumber => 'Masa numarası';

  @override
  String get tableNumberHint => 'Masa numaranızı girin';

  @override
  String get subtotal => 'Ara toplam';

  @override
  String get vat => 'KDV';

  @override
  String vatRate(String rate) {
    return 'KDV %$rate';
  }

  @override
  String get total => 'Toplam';

  @override
  String get rounding => 'Yuvarlama';

  @override
  String get placeOrder => 'Sipariş Ver';

  @override
  String get orderSummary => 'Sipariş Özeti';

  @override
  String get yourName => 'Adınız (opsiyonel)';

  @override
  String get yourNameHint => 'örn. Ayşe';

  @override
  String get orderNotes => 'Sipariş notu';

  @override
  String get orderNotesHint => 'Mutfak için notunuz';

  @override
  String get confirmOrder => 'Siparişi Onayla';

  @override
  String get orderPlaced => 'Sipariş alındı!';

  @override
  String orderNumber(String number) {
    return 'Sipariş #$number';
  }

  @override
  String estimatedWait(String minutes) {
    return 'Tahmini bekleme: $minutes dk';
  }

  @override
  String get orderSentToKitchen => 'Siparişiniz mutfağa iletildi.';

  @override
  String get trackOrder => 'Siparişi Takip Et';

  @override
  String get orderStatus => 'Sipariş Durumu';

  @override
  String get statusReceived => 'Sipariş alındı';

  @override
  String get statusPreparing => 'Hazırlanıyor';

  @override
  String get statusReady => 'Hazır!';

  @override
  String get statusServed => 'Servis edildi';

  @override
  String get backToMenu => 'Menüye Dön';

  @override
  String get remove => 'Kaldır';

  @override
  String get edit => 'Düzenle';

  @override
  String get close => 'Kapat';

  @override
  String get language => 'Dil';

  @override
  String get required => 'Zorunlu';

  @override
  String get optional => 'Opsiyonel';

  @override
  String get outOfStock => 'Mevcut değil';

  @override
  String get customize => 'Özelleştir';

  @override
  String get chooseOne => 'Bir seçim yapın';

  @override
  String chooseUpTo(String max) {
    return 'En fazla $max seçin';
  }

  @override
  String chooseAtLeast(String min) {
    return 'En az $min seçin';
  }

  @override
  String get free => 'Ücretsiz';

  @override
  String get itemAdded => 'Sepete eklendi';

  @override
  String get errorLoadingMenu => 'Menü yüklenemedi. Lütfen tekrar deneyin.';

  @override
  String get retry => 'Tekrar dene';

  @override
  String get orderFailed => 'Sipariş gönderilemedi. Lütfen tekrar deneyin.';

  @override
  String get loading => 'Yükleniyor…';

  @override
  String get chf => 'CHF';

  @override
  String get modifiers => 'Seçenekler';

  @override
  String tableAutoFilled(String number) {
    return 'Masa $number QR koddan otomatik dolduruldu';
  }

  @override
  String get selectTableNumber => 'Lütfen masa numaranızı girin';

  @override
  String get continueToCheckout => 'Ödemeye Devam';

  @override
  String get orderTypeRequired => 'Lütfen masada veya paket seçin';

  @override
  String itemsInCart(String count) {
    return 'Sepette $count ürün';
  }
}
