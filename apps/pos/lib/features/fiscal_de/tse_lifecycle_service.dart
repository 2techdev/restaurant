/// TSE lifecycle manager for German KassenSichV compliance.
///
/// Orchestrates the TSE state machine:
///   CREATED → INITIALIZED → ACTIVE → (DISABLED)
///
/// Also exposes self-test and client registration which are required before
/// the TSE can sign transactions.
library;

import 'package:uuid/uuid.dart';
import 'fiskaly_models.dart';
import 'fiskaly_service.dart';

/// Represents the full local state of the TSE (includes registration status).
class TseLifecycleState {
  const TseLifecycleState({
    required this.tseState,
    required this.isClientRegistered,
    this.tseInfo,
    this.lastSelfTestAt,
    this.lastError,
  });

  final TseState tseState;
  final bool isClientRegistered;
  final TseInfo? tseInfo;
  final DateTime? lastSelfTestAt;
  final String? lastError;

  bool get isReady =>
      tseState == TseState.active && isClientRegistered;

  TseLifecycleState copyWith({
    TseState? tseState,
    bool? isClientRegistered,
    TseInfo? tseInfo,
    DateTime? lastSelfTestAt,
    String? lastError,
  }) =>
      TseLifecycleState(
        tseState: tseState ?? this.tseState,
        isClientRegistered:
            isClientRegistered ?? this.isClientRegistered,
        tseInfo: tseInfo ?? this.tseInfo,
        lastSelfTestAt: lastSelfTestAt ?? this.lastSelfTestAt,
        lastError: lastError ?? this.lastError,
      );

  static const initial = TseLifecycleState(
    tseState: TseState.unknown,
    isClientRegistered: false,
  );
}

/// Manages the TSE lifecycle end-to-end.
///
/// Wraps [FiskalyService] with higher-level operations and keeps track of
/// state transitions needed before signing is possible.
class TseLifecycleService {
  TseLifecycleService({required this.service});

  final FiskalyService service;

  static const _uuid = Uuid();

  // ---------------------------------------------------------------------------
  // Full initialization flow
  // ---------------------------------------------------------------------------

  /// Runs the complete initialization flow for a new TSE installation.
  ///
  /// Steps:
  ///   1. Create TSE (idempotent) → CREATED
  ///   2. Initialize TSE (set admin PIN) → INITIALIZED
  ///   3. Activate TSE → ACTIVE
  ///   4. Register this POS client
  ///
  /// If the TSE already exists and is ACTIVE, only step 4 is needed.
  /// Returns the final [TseLifecycleState].
  Future<TseLifecycleState> initialize({
    String? tseId,
    String? clientId,
    String? clientSerialNumber,
  }) async {
    final resolvedTseId = tseId ?? _uuid.v4();
    final resolvedClientId = clientId ?? _uuid.v4();
    final serialNumber =
        clientSerialNumber ?? 'GASTROCORE-${resolvedClientId.substring(0, 8).toUpperCase()}';

    TseInfo info;

    // Step 1: create TSE (PUT is idempotent)
    info = await service.createTse(resolvedTseId);

    // Step 2: initialize if needed
    if (info.state == TseState.created) {
      info = await service.initializeTse(
        resolvedTseId,
        adminPin: service.config.adminPin,
      );
    }

    // Step 3: activate if needed
    if (info.state == TseState.initialized) {
      info = await service.activateTse(
        resolvedTseId,
        adminPin: service.config.adminPin,
      );
    }

    // Step 4: register client
    await service.registerClient(
      resolvedTseId,
      resolvedClientId,
      serialNumber: serialNumber,
    );

    // Update config with resolved IDs
    service.config = service.config.copyWith(
      tseId: resolvedTseId,
      clientId: resolvedClientId,
    );

    return TseLifecycleState(
      tseState: info.state,
      isClientRegistered: true,
      tseInfo: info,
    );
  }

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  /// Fetches the current TSE state from Fiskaly.
  Future<TseLifecycleState> getState() async {
    final tseId = service.config.tseId;
    if (tseId == null) {
      return TseLifecycleState.initial;
    }
    final info = await service.getTseInfo(tseId);
    return TseLifecycleState(
      tseState: info.state,
      isClientRegistered: service.config.clientId != null,
      tseInfo: info,
    );
  }

  // ---------------------------------------------------------------------------
  // Self-test
  // ---------------------------------------------------------------------------

  /// Runs the TSE self-test (BSI TR-03153 §4.6.2).
  ///
  /// Should be called at startup and periodically (recommended: daily).
  Future<TseLifecycleState> runSelfTest() async {
    final tseId = service.config.tseId;
    if (tseId == null) {
      throw const FiskalyException('TSE not initialized — no tseId configured');
    }
    final info = await service.runSelfTest(tseId);
    return TseLifecycleState(
      tseState: info.state,
      isClientRegistered: service.config.clientId != null,
      tseInfo: info,
      lastSelfTestAt: DateTime.now(),
    );
  }

  // ---------------------------------------------------------------------------
  // Transaction helpers
  // ---------------------------------------------------------------------------

  /// Starts a Fiskaly transaction for the given [transactionId].
  ///
  /// Throws [FiskalyException] if the TSE is not configured or not active.
  Future<FiskalyTransaction> startTransaction(String transactionId) async {
    _assertReady();
    return service.startTransaction(
      tseId: service.config.tseId!,
      transactionId: transactionId,
      clientId: service.config.clientId!,
    );
  }

  /// Finishes and signs a Fiskaly transaction.
  Future<FiskalyTransaction> finishTransaction({
    required String transactionId,
    required List<VatAmountPerRate> amountsPerVatRate,
    required String paymentType,
    required double paymentAmount,
    int txRevision = 2,
  }) async {
    _assertReady();
    return service.finishTransaction(
      tseId: service.config.tseId!,
      transactionId: transactionId,
      clientId: service.config.clientId!,
      amountsPerVatRate: amountsPerVatRate,
      paymentType: paymentType,
      paymentAmount: paymentAmount,
      txRevision: txRevision,
    );
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  /// Triggers a DSFinV-K export on Fiskaly.
  Future<ExportState> triggerExport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final tseId = service.config.tseId;
    if (tseId == null) {
      throw const FiskalyException('TSE not initialized — no tseId configured');
    }
    return service.triggerExport(tseId,
        startDate: startDate, endDate: endDate);
  }

  /// Polls export status.
  Future<ExportState> getExportStatus(String exportId) async {
    final tseId = service.config.tseId;
    if (tseId == null) {
      throw const FiskalyException('TSE not initialized — no tseId configured');
    }
    return service.getExportStatus(tseId, exportId);
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _assertReady() {
    if (service.config.tseId == null) {
      throw const FiskalyException(
          'TSE not ready — tseId not set. Run initialize() first.');
    }
    if (service.config.clientId == null) {
      throw const FiskalyException(
          'TSE not ready — clientId not set. Run initialize() first.');
    }
  }
}
