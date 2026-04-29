// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appTitle => 'GastroCore Dashboard';

  @override
  String get login => 'Giriş';

  @override
  String get logout => 'Çıkış';

  @override
  String get email => 'E-posta adresi';

  @override
  String get password => 'Şifre';

  @override
  String get rememberMe => 'Oturumu açık tut';

  @override
  String get loginSubtitle => 'Restoran müdürleri için erişim';

  @override
  String get loginError => 'Geçersiz e-posta veya şifre';

  @override
  String get dashboard => 'Gösterge Paneli';

  @override
  String get orders => 'Siparişler';

  @override
  String get menu => 'Menü';

  @override
  String get reports => 'Raporlar';

  @override
  String get settings => 'Ayarlar';

  @override
  String get totalRevenue => 'Günlük ciro';

  @override
  String get orderCount => 'Sipariş sayısı';

  @override
  String get avgTicket => 'Ort. fiş';

  @override
  String get activeOrders => 'Aktif siparişler';

  @override
  String get tablesOccupied => 'Dolu masalar';

  @override
  String get staffOnShift => 'Vardiyadaki personel';

  @override
  String get topItems => 'Günün en çok satanları';

  @override
  String get revenueChart => 'Ciro grafiği';

  @override
  String get last7Days => 'Son 7 gün';

  @override
  String get last30Days => 'Son 30 gün';

  @override
  String get last90Days => 'Son 90 gün';

  @override
  String get refresh => 'Yenile';

  @override
  String get allOrders => 'Tüm siparişler';

  @override
  String get filterByDate => 'Tarihe göre filtrele';

  @override
  String get filterByStatus => 'Duruma göre filtrele';

  @override
  String get exportCsv => 'CSV dışa aktar';

  @override
  String orderNumber(String number) {
    return 'Sipariş #$number';
  }

  @override
  String get paid => 'Ödendi';

  @override
  String get open => 'Açık';

  @override
  String get preparing => 'Hazırlanıyor';

  @override
  String get closed => 'Kapandı';

  @override
  String get cancelled => 'İptal edildi';

  @override
  String get dineIn => 'Masada';

  @override
  String get takeaway => 'Paket';

  @override
  String get categories => 'Kategoriler';

  @override
  String get products => 'Ürünler';

  @override
  String get addProduct => 'Ürün ekle';

  @override
  String get addCategory => 'Kategori ekle';

  @override
  String get editProduct => 'Ürünü düzenle';

  @override
  String get available => 'Mevcut';

  @override
  String get price => 'Fiyat';

  @override
  String get taxGroup => 'Vergi grubu';

  @override
  String get dailyReport => 'Günlük';

  @override
  String get weeklyReport => 'Haftalık';

  @override
  String get monthlyReport => 'Aylık';

  @override
  String get salesByCategory => 'Kategoriye göre satış';

  @override
  String get paymentBreakdown => 'Ödeme yöntemleri';

  @override
  String get staffPerformance => 'Personel performansı';

  @override
  String get mwstReport => 'KDV raporu';

  @override
  String get restaurantInfo => 'Restoran bilgileri';

  @override
  String get printerConfig => 'Yazıcı ayarları';

  @override
  String get taxSettings => 'Vergi ayarları';

  @override
  String get userManagement => 'Kullanıcı yönetimi';

  @override
  String get save => 'Kaydet';

  @override
  String get cancel => 'İptal';

  @override
  String get add => 'Ekle';

  @override
  String get edit => 'Düzenle';

  @override
  String get delete => 'Sil';

  @override
  String get from => 'Başlangıç';

  @override
  String get to => 'Bitiş';

  @override
  String get apply => 'Uygula';

  @override
  String get today => 'Bugün';

  @override
  String get yesterday => 'Dün';

  @override
  String get thisWeek => 'Bu hafta';

  @override
  String get thisMonth => 'Bu ay';

  @override
  String get chf => 'CHF';

  @override
  String get loading => 'Yükleniyor…';

  @override
  String get noData => 'Veri yok';

  @override
  String get error => 'Hata';

  @override
  String get retry => 'Tekrar dene';

  @override
  String get darkMode => 'Koyu tema';

  @override
  String get lightMode => 'Açık tema';

  @override
  String get language => 'Dil';

  @override
  String get copiedToClipboard => 'Panoya kopyalandı';

  @override
  String get saveSuccess => 'Değişiklikler kaydedildi';
}
