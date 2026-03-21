import 'printer_device.dart';

/// Her bağlantı türü (WiFi, USB, Bluetooth) için ortak arayüz.
///
/// Yeni bir bağlantı türü eklemek için bu sınıfı genişletin ve
/// [PrinterService] içinde kaydedin.
abstract class PrinterProviderInterface {
  /// Bu provider'ın desteklediği cihazları keşfeder.
  ///
  /// WiFi provider'ı boş liste döndürür (IP elle girilir).
  /// USB provider'ı bağlı USB yazıcıları listeler.
  /// Bluetooth provider'ı eşleşmiş BT cihazlarını listeler.
  Future<List<PrinterDevice>> discoverDevices();

  /// Belirtilen cihaza bağlanır.
  ///
  /// Başarılı olursa `true`, aksi hâlde `false` döndürür.
  Future<bool> connect(PrinterDevice device);

  /// Mevcut bağlantıyı keser.
  Future<void> disconnect();

  /// Ham ESC/POS byte'larını yazıcıya gönderir.
  ///
  /// Yazıcı bağlı değilse veya gönderim başarısız olursa `false` döndürür.
  Future<bool> sendBytes(List<int> bytes);

  /// Provider'ın şu an bağlı olup olmadığı.
  bool get isConnected;

  /// Mevcut bağlantı için oturum açılmış cihaz; bağlı değilse `null`.
  PrinterDevice? get connectedDevice;
}
