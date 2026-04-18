// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appTitle => 'GastroCore POS';

  @override
  String get navHome => 'Ana Sayfa';

  @override
  String get navOrders => 'Siparişler';

  @override
  String get navTables => 'Masalar';

  @override
  String get navMenu => 'Menü';

  @override
  String get navShift => 'Vardiya';

  @override
  String get navSettings => 'Ayarlar';

  @override
  String get navReports => 'Raporlar';

  @override
  String get navKitchen => 'Mutfak';

  @override
  String get posNewOrder => 'Yeni Sipariş';

  @override
  String get posOrder => 'Sipariş';

  @override
  String get posPayment => 'Ödeme';

  @override
  String get posCash => 'Nakit';

  @override
  String get posCard => 'Kart';

  @override
  String get posTwint => 'TWINT';

  @override
  String get posTotal => 'Toplam';

  @override
  String get posSubtotal => 'Ara Toplam';

  @override
  String get posVat => 'KDV';

  @override
  String get posDiscount => 'İndirim';

  @override
  String get posCancel => 'İptal';

  @override
  String get posRefund => 'İade';

  @override
  String get posCharge => 'Tahsil Et';

  @override
  String get posGiven => 'Alınan';

  @override
  String get posChange => 'Para Üstü';

  @override
  String get posSplitBill => 'Hesabı Böl';

  @override
  String get posOrderType => 'Sipariş Tipi';

  @override
  String get posDineIn => 'Masada';

  @override
  String get posTakeaway => 'Paket';

  @override
  String get posDelivery => 'Eve Teslim';

  @override
  String get tableEmpty => 'Boş';

  @override
  String get tableOccupied => 'Dolu';

  @override
  String get tableReserved => 'Rezerve';

  @override
  String get tableDirty => 'Temizlenecek';

  @override
  String get tableMerge => 'Birleştir';

  @override
  String get tableTransfer => 'Aktar';

  @override
  String tableGuest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kişi',
      one: '1 kişi',
    );
    return '$_temp0';
  }

  @override
  String get tableNewTable => 'Yeni Masa';

  @override
  String get tableFloor => 'Bölge';

  @override
  String get tableCapacity => 'Kapasite';

  @override
  String get shiftOpen => 'Aç';

  @override
  String get shiftClose => 'Kapat';

  @override
  String get shiftCashCount => 'Kasa Sayımı';

  @override
  String get shiftDifference => 'Fark';

  @override
  String get shiftZReport => 'Z Raporu';

  @override
  String get shiftXReport => 'X Raporu (Ara)';

  @override
  String get shiftOpenShift => 'Vardiya Aç';

  @override
  String get shiftCloseShift => 'Vardiya Kapat';

  @override
  String get shiftOpeningFloat => 'Açılış Kasası';

  @override
  String get shiftCashIn => 'Kasa Girişi';

  @override
  String get shiftCashOut => 'Kasa Çıkışı';

  @override
  String get shiftNoActiveShift => 'Aktif Vardiya Yok';

  @override
  String get shiftOpenCashDrawer => 'Çekmeceyi Aç';

  @override
  String get receiptNo => 'Fiş No';

  @override
  String get receiptDate => 'Tarih';

  @override
  String get receiptTime => 'Saat';

  @override
  String get receiptCashier => 'Kasiyer';

  @override
  String get receiptThankYou => 'Teşekkür ederiz!';

  @override
  String get receiptTable => 'Masa';

  @override
  String get settingsPrinter => 'Yazıcı';

  @override
  String get settingsPayment => 'Ödeme';

  @override
  String get settingsLanguage => 'Dil';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsBackup => 'Yedekleme';

  @override
  String get settingsRestaurant => 'Restoran';

  @override
  String get settingsTax => 'Vergi (KDV)';

  @override
  String get settingsReceipt => 'Fiş';

  @override
  String get settingsAppearance => 'Görünüm';

  @override
  String get settingsAbout => 'Hakkında';

  @override
  String get settingsDemoData => 'Demo Veriler';

  @override
  String get actionSave => 'Kaydet';

  @override
  String get actionCancel => 'İptal';

  @override
  String get actionDelete => 'Sil';

  @override
  String get actionEdit => 'Düzenle';

  @override
  String get actionAdd => 'Ekle';

  @override
  String get actionSearch => 'Ara';

  @override
  String get actionFilter => 'Filtrele';

  @override
  String get actionConfirm => 'Tamam';

  @override
  String get actionClose => 'Kapat';

  @override
  String get actionBack => 'Geri';

  @override
  String get actionPrint => 'Yazdır';

  @override
  String get actionRefresh => 'Yenile';

  @override
  String get statusError => 'Hata';

  @override
  String get statusSuccess => 'Başarılı';

  @override
  String get statusLoading => 'Yükleniyor...';

  @override
  String get statusNoData => 'Veri yok';

  @override
  String get statusOffline => 'Çevrimdışı';

  @override
  String get statusOnline => 'Çevrimiçi';

  @override
  String get menuCategory => 'Kategori';

  @override
  String get menuProduct => 'Ürün';

  @override
  String get menuPrice => 'Fiyat';

  @override
  String get menuModifier => 'Ek Seçenek';

  @override
  String get menuActive => 'Aktif';

  @override
  String get menuInactive => 'Pasif';

  @override
  String get orderHistory => 'Sipariş Geçmişi';

  @override
  String get orderStatus => 'Durum';

  @override
  String get orderStatusOpen => 'Açık';

  @override
  String get orderStatusPaid => 'Ödendi';

  @override
  String get orderStatusCancelled => 'İptal Edildi';

  @override
  String get orderStatusRefunded => 'İade Edildi';

  @override
  String get dashboardDailyRevenue => 'Günlük Ciro';

  @override
  String get dashboardOrders => 'Siparişler';

  @override
  String get dashboardAvgOrder => 'Ort. Sipariş';

  @override
  String get dashboardTableOccupancy => 'Masa Doluluğu';

  @override
  String get dashboardRecentOrders => 'Son Siparişler';

  @override
  String get dashboardHourlySales => 'Saatlik Satış';

  @override
  String get floorPlan => 'Salon Planı';

  @override
  String get editMode => 'Düzenleme Modu';

  @override
  String get confirmDelete => 'Silmeyi Onayla';

  @override
  String get confirmDeleteMessage =>
      'Bu kaydı silmek istediğinizden emin misiniz?';

  @override
  String get pinLogin => 'PIN girin';

  @override
  String get pinWrong => 'Yanlış PIN';

  @override
  String get shiftStatusOpen => 'Vardiya Açık';

  @override
  String get shiftNoShiftTapToOpen => 'Vardiya yok – açmak için dokunun';

  @override
  String get quickActionNewOrder => 'Yeni Sipariş';

  @override
  String get quickActionFloorPlan => 'Salon Planı';

  @override
  String get quickActionOpenShift => 'Vardiya Aç';

  @override
  String get quickActionCloseShift => 'Vardiya Kapat';

  @override
  String get quickActionOrderHistory => 'Sipariş Geçmişi';

  @override
  String get navCustomers => 'Müşteriler';

  @override
  String get crmTitle => 'Müşteri Yönetimi';

  @override
  String get crmNewCustomer => 'Yeni Müşteri';

  @override
  String get crmEditCustomer => 'Müşteri Düzenle';

  @override
  String get crmDeleteCustomer => 'Müşteri Sil';

  @override
  String get crmName => 'Ad';

  @override
  String get crmPhone => 'Telefon';

  @override
  String get crmEmail => 'E-posta';

  @override
  String get crmAddress => 'Adres';

  @override
  String get crmBirthday => 'Doğum Günü';

  @override
  String get crmNotes => 'Notlar';

  @override
  String get crmTotalOrders => 'Siparişler';

  @override
  String get crmTotalSpent => 'Ciro';

  @override
  String get crmLoyaltyPoints => 'Sadakat Puanı';

  @override
  String get crmTierBronze => 'Bronz';

  @override
  String get crmTierSilver => 'Gümüş';

  @override
  String get crmTierGold => 'Altın';

  @override
  String crmBirthdayReminder(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count doğum günü',
      one: '1 doğum günü',
    );
    return '$_temp0';
  }

  @override
  String get loyaltyTitle => 'Sadakat Puanı';

  @override
  String get loyaltyRedeem => 'Puan Kullan';

  @override
  String get loyaltyAdjust => 'Puan Düzenle';

  @override
  String get loyaltyEarnRule => '1 CHF harca = 1 puan kazan';

  @override
  String get loyaltyRedeemRule => '100 puan = CHF 1.00 indirim';

  @override
  String get loyaltyTransactionEarn => 'Puan kazanıldı';

  @override
  String get loyaltyTransactionRedeem => 'Puan kullanıldı';

  @override
  String get loyaltyTransactionAdjust => 'Manuel düzeltme';

  @override
  String get loyaltyTransactionExpire => 'Puan süresi doldu';

  @override
  String get reservationNew => 'Yeni Rezervasyon';

  @override
  String get reservationEdit => 'Rezervasyon Düzenle';

  @override
  String get reservationNoShow => 'Gelmedi';

  @override
  String get reservationCancel => 'Rezervasyon İptal';

  @override
  String get reservationErrorTimeRange =>
      'Bitiş saati başlangıçtan sonra olmalı';

  @override
  String get reservationErrorConflict =>
      'Bu zaman aralığı mevcut bir rezervasyonla çakışıyor';

  @override
  String get reservationCustomerInfo => 'Müşteri Bilgileri';

  @override
  String get reservationCustomerName => 'Müşteri Adı';

  @override
  String get reservationNameRequired => 'Ad zorunlu';

  @override
  String get reservationCustomerPhone => 'Telefon Numarası';

  @override
  String get reservationCustomerEmail => 'E-posta Adresi';

  @override
  String courseLabel(String number) {
    String _temp0 = intl.Intl.selectLogic(number, {
      '1': 'Gang 1',
      '2': 'Gang 2',
      '3': 'Gang 3',
      '4': 'Gang 4',
      '5': 'Gang 5',
      'other': 'Gang $number',
    });
    return '$_temp0';
  }

  @override
  String get menuCategoryStarter => 'Antre';

  @override
  String get menuCategoryMain => 'Ana Yemek';

  @override
  String get menuCategoryDessert => 'Tatlı';

  @override
  String get posServiceCharge => 'Servis bedeli';

  @override
  String get posCover => 'Kişi sayısı';

  @override
  String get settingsLocale => 'Dil ve Bölge';

  @override
  String get fiscalReceiptVat => 'KDV';
}
