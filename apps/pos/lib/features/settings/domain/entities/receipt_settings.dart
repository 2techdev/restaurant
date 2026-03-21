/// Receipt / ticket layout settings entity.
///
/// Controls header/footer text, logo visibility, and optional QR code
/// printed at the bottom of the receipt.
library;

import 'dart:convert';

class ReceiptSettings {
  const ReceiptSettings({
    this.headerText = '',
    this.footerText = 'Merci de votre visite! · Danke für Ihren Besuch!',
    this.showLogo = true,
    this.showQrCode = false,
    this.qrCodeData = '',
  });

  /// Text printed below the logo in the receipt header.
  final String headerText;

  /// Text printed at the very bottom of the receipt.
  final String footerText;

  /// Whether to print the restaurant logo on receipts.
  final bool showLogo;

  /// Whether to print a QR code at the bottom of the receipt.
  final bool showQrCode;

  /// URL or text to encode in the receipt QR code (e.g. Google Reviews link).
  final String qrCodeData;

  ReceiptSettings copyWith({
    String? headerText,
    String? footerText,
    bool? showLogo,
    bool? showQrCode,
    String? qrCodeData,
  }) =>
      ReceiptSettings(
        headerText: headerText ?? this.headerText,
        footerText: footerText ?? this.footerText,
        showLogo: showLogo ?? this.showLogo,
        showQrCode: showQrCode ?? this.showQrCode,
        qrCodeData: qrCodeData ?? this.qrCodeData,
      );

  Map<String, dynamic> toJson() => {
        'headerText': headerText,
        'footerText': footerText,
        'showLogo': showLogo,
        'showQrCode': showQrCode,
        'qrCodeData': qrCodeData,
      };

  factory ReceiptSettings.fromJson(Map<String, dynamic> json) =>
      ReceiptSettings(
        headerText: (json['headerText'] as String?) ?? '',
        footerText: (json['footerText'] as String?) ??
            'Merci de votre visite! · Danke für Ihren Besuch!',
        showLogo: (json['showLogo'] as bool?) ?? true,
        showQrCode: (json['showQrCode'] as bool?) ?? false,
        qrCodeData: (json['qrCodeData'] as String?) ?? '',
      );

  String toJsonString() => jsonEncode(toJson());

  factory ReceiptSettings.fromJsonString(String s) =>
      ReceiptSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReceiptSettings &&
          headerText == other.headerText &&
          footerText == other.footerText &&
          showLogo == other.showLogo &&
          showQrCode == other.showQrCode &&
          qrCodeData == other.qrCodeData;

  @override
  int get hashCode =>
      Object.hash(headerText, footerText, showLogo, showQrCode, qrCodeData);
}
