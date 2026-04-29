/// Riverpod wiring for the update checker.
///
/// Three providers:
///   * [updateServiceProvider] — singleton HTTP-backed [UpdateService]
///   * [updateChannelSettingsProvider] — persisted manifest URL / channel
///   * [updateCheckControllerProvider] — notifier driving the Settings UI
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/services/audit_service.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';
import 'package:gastrocore_pos/features/audit_log/presentation/providers/audit_log_provider.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/update_channel_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/repositories/settings_repository.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';
import 'package:gastrocore_pos/features/updates/data/update_service.dart';
import 'package:gastrocore_pos/features/updates/domain/app_version.dart';
import 'package:gastrocore_pos/features/updates/domain/entities/update_manifest.dart';

// ---------------------------------------------------------------------------
// UpdateService singleton
// ---------------------------------------------------------------------------

final updateServiceProvider = Provider<UpdateService>((ref) {
  final service = UpdateService();
  ref.onDispose(service.dispose);
  return service;
});

// ---------------------------------------------------------------------------
// UpdateChannelSettings persistence
// ---------------------------------------------------------------------------

class UpdateChannelSettingsNotifier
    extends StateNotifier<AsyncValue<UpdateChannelSettings>> {
  UpdateChannelSettingsNotifier(this._repository)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final SettingsRepository? _repository;

  Future<void> _load() async {
    final repo = _repository;
    if (repo == null) {
      state = const AsyncValue.data(UpdateChannelSettings());
      return;
    }
    state = await AsyncValue.guard(repo.loadUpdateChannelSettings);
  }

  Future<void> save(UpdateChannelSettings settings) async {
    await _repository?.saveUpdateChannelSettings(settings);
    state = AsyncValue.data(settings);
  }

  Future<void> update(
    UpdateChannelSettings Function(UpdateChannelSettings) updater,
  ) async {
    final current = state.valueOrNull ?? const UpdateChannelSettings();
    await save(updater(current));
  }
}

final updateChannelSettingsProvider = StateNotifierProvider<
    UpdateChannelSettingsNotifier, AsyncValue<UpdateChannelSettings>>((ref) {
  final repo = ref.watch(settingsRepositoryProvider).valueOrNull;
  return UpdateChannelSettingsNotifier(repo);
});

// ---------------------------------------------------------------------------
// Update check controller — drives the Settings → Güncelleme UI
// ---------------------------------------------------------------------------

/// Immutable view-state for the update check screen.
class UpdateCheckState {
  const UpdateCheckState({
    this.isChecking = false,
    this.manifest,
    this.errorMessage,
    this.checkedAt,
  });

  final bool isChecking;
  final UpdateManifest? manifest;
  final String? errorMessage;
  final DateTime? checkedAt;

  bool get hasNewer =>
      manifest != null && manifest!.isNewerThan(appBuildNumber);

  UpdateCheckState copyWith({
    bool? isChecking,
    UpdateManifest? manifest,
    String? errorMessage,
    DateTime? checkedAt,
    bool clearError = false,
    bool clearManifest = false,
  }) =>
      UpdateCheckState(
        isChecking: isChecking ?? this.isChecking,
        manifest: clearManifest ? null : (manifest ?? this.manifest),
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        checkedAt: checkedAt ?? this.checkedAt,
      );
}

class UpdateCheckController extends StateNotifier<UpdateCheckState> {
  UpdateCheckController({
    required UpdateService service,
    required SettingsRepository? settings,
    AuditService? audit,
  })  : _service = service,
        _settings = settings,
        _audit = audit,
        super(const UpdateCheckState());

  final UpdateService _service;
  final SettingsRepository? _settings;
  final AuditService? _audit;

  /// Fetches the manifest at the configured URL, updates state and audits
  /// the check. Returns the manifest on success, or null on error.
  Future<UpdateManifest?> checkNow() async {
    if (state.isChecking) return state.manifest;
    final settings = _settings;
    if (settings == null) {
      state = state.copyWith(
        errorMessage: 'Ayarlar henüz yüklenmedi — bir saniye sonra deneyin.',
        checkedAt: DateTime.now(),
      );
      return null;
    }
    state = state.copyWith(
      isChecking: true,
      clearError: true,
      clearManifest: true,
    );

    final channel = await settings.loadUpdateChannelSettings();
    if (channel.manifestUrl.trim().isEmpty) {
      state = state.copyWith(
        isChecking: false,
        errorMessage: 'Güncelleme kanalı URL\'i ayarlanmamış.',
        checkedAt: DateTime.now(),
      );
      return null;
    }

    try {
      final manifest = await _service.fetchManifest(channel.manifestUrl);
      final now = DateTime.now();
      state = UpdateCheckState(
        isChecking: false,
        manifest: manifest,
        checkedAt: now,
      );
      await settings.saveUpdateChannelSettings(
        channel.copyWith(
          lastCheckEpochMs: now.millisecondsSinceEpoch,
          lastSeenBuild: manifest.buildNumber,
        ),
      );
      await _audit?.log(
        action: AuditAction.settingChanged,
        entityType: 'app_update_check',
        entityId: manifest.buildNumber.toString(),
        newValueJson: manifest.toJsonString(),
        reason: manifest.isNewerThan(appBuildNumber)
            ? 'newer build available'
            : 'already up to date',
      );
      return manifest;
    } on UpdateServiceException catch (e) {
      state = state.copyWith(
        isChecking: false,
        errorMessage: e.message,
        checkedAt: DateTime.now(),
      );
      return null;
    } catch (e) {
      state = state.copyWith(
        isChecking: false,
        errorMessage: 'Beklenmeyen hata: $e',
        checkedAt: DateTime.now(),
      );
      return null;
    }
  }

  /// Opens the APK download URL via the system share sheet and audits the
  /// handoff. Returns true on success.
  Future<bool> openDownload() async {
    final manifest = state.manifest;
    if (manifest == null) return false;
    try {
      await _service.openDownload(manifest.apkUrl);
      await _audit?.log(
        action: AuditAction.settingChanged,
        entityType: 'app_update_download',
        entityId: manifest.buildNumber.toString(),
        newValueJson: '{"apkUrl":"${manifest.apkUrl}"}',
        reason: 'operator opened download',
      );
      return true;
    } on UpdateServiceException catch (e) {
      state = state.copyWith(errorMessage: e.message);
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final updateCheckControllerProvider =
    StateNotifierProvider<UpdateCheckController, UpdateCheckState>((ref) {
  final service = ref.watch(updateServiceProvider);
  final repo = ref.watch(settingsRepositoryProvider).valueOrNull;
  // Audit wiring is best-effort — if the DI graph has not booted yet the
  // controller simply skips the log.
  AuditService? audit;
  try {
    audit = ref.read(auditServiceProvider);
  } catch (_) {
    audit = null;
  }
  return UpdateCheckController(
    service: service,
    settings: repo,
    audit: audit,
  );
});
