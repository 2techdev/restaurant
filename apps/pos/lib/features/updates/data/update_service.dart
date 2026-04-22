/// Fetches the update manifest and brokers the download handoff.
///
/// Kept deliberately thin so the provider layer can inject a fake [http.Client]
/// in tests. The service only *reads* the network — the actual APK download
/// is handed to the platform (share sheet / browser) so the pilot does not
/// need install-packages permissions.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import 'package:gastrocore_pos/features/updates/domain/entities/update_manifest.dart';

class UpdateServiceException implements Exception {
  const UpdateServiceException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause != null
      ? 'UpdateServiceException: $message (cause: $cause)'
      : 'UpdateServiceException: $message';
}

class UpdateService {
  UpdateService({
    http.Client? client,
    Duration? timeout,
  })  : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 10);

  final http.Client _client;
  final Duration _timeout;

  /// Fetches the manifest at [manifestUrl] and returns the parsed entity.
  ///
  /// Throws [UpdateServiceException] for anything the operator can act on
  /// (bad URL, 404, timeout, unparseable JSON). Network errors are wrapped
  /// so the UI layer can render a single "check failed" card.
  Future<UpdateManifest> fetchManifest(String manifestUrl) async {
    final trimmed = manifestUrl.trim();
    if (trimmed.isEmpty) {
      throw const UpdateServiceException(
        'Güncelleme kanalı URL\'i ayarlanmamış.',
      );
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw UpdateServiceException('Geçersiz URL: $trimmed');
    }

    http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeout);
    } on Exception catch (e) {
      throw UpdateServiceException(
        'Güncelleme sunucusuna ulaşılamıyor.',
        cause: e,
      );
    }

    if (response.statusCode != 200) {
      throw UpdateServiceException(
        'Manifest alınamadı (HTTP ${response.statusCode}).',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Manifest root must be a JSON object');
      }
      return UpdateManifest.fromJson(decoded);
    } catch (e) {
      throw UpdateServiceException('Manifest JSON ayrıştırılamadı.', cause: e);
    }
  }

  /// Hands the APK URL to the platform share sheet so the operator can pick
  /// their default browser (or push it to a download manager). We avoid
  /// url_launcher + INSTALL_PACKAGES: the pilot is sideloaded and the
  /// operator is expected to confirm the download + install by hand.
  Future<void> openDownload(String apkUrl) async {
    final trimmed = apkUrl.trim();
    if (trimmed.isEmpty) {
      throw const UpdateServiceException('İndirme URL\'i boş.');
    }
    try {
      await Share.share(
        trimmed,
        subject: 'GastroCore POS güncellemesi',
      );
    } on Exception catch (e) {
      throw UpdateServiceException('Paylaşım açılamadı.', cause: e);
    }
  }

  /// Releases the underlying HTTP client. Called from the provider's
  /// onDispose and from tests after each `MockClient` scenario.
  void dispose() => _client.close();
}
