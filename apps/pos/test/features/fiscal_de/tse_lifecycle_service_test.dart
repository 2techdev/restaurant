import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/fiscal_de/fiskaly_models.dart';
import 'package:gastrocore_pos/features/fiscal_de/fiskaly_service.dart';
import 'package:gastrocore_pos/features/fiscal_de/tse_lifecycle_service.dart';

// ---------------------------------------------------------------------------
// Fake FiskalyService
// ---------------------------------------------------------------------------

class _FakeFiskalyService extends FiskalyService {
  _FakeFiskalyService({required super.config});

  var createTseCalled = false;
  var initializeTseCalled = false;
  var activateTseCalled = false;
  var registerClientCalled = false;
  var runSelfTestCalled = false;
  var startTransactionCalled = false;
  var finishTransactionCalled = false;

  TseState _stateToReturn = TseState.created;

  void setStateToReturn(TseState s) => _stateToReturn = s;

  TseInfo _makeTseInfo() => TseInfo(
        id: 'fake-tse-id',
        state: _stateToReturn,
        serialNumber: 'DEADBEEF',
        signatureAlgorithm: 'ecdsa-plain-SHA384',
        signatureCounter: 0,
      );

  @override
  Future<TseInfo> createTse(String tseId, {String description = 'GastroCore POS'}) async {
    createTseCalled = true;
    return _makeTseInfo();
  }

  @override
  Future<TseInfo> getTseInfo(String tseId) async => _makeTseInfo();

  @override
  Future<TseInfo> initializeTse(String tseId, {required String adminPin}) async {
    initializeTseCalled = true;
    _stateToReturn = TseState.initialized;
    return _makeTseInfo();
  }

  @override
  Future<TseInfo> activateTse(String tseId, {required String adminPin}) async {
    activateTseCalled = true;
    _stateToReturn = TseState.active;
    return _makeTseInfo();
  }

  @override
  Future<void> registerClient(
    String tseId,
    String clientId, {
    required String serialNumber,
  }) async {
    registerClientCalled = true;
  }

  @override
  Future<TseInfo> runSelfTest(String tseId) async {
    runSelfTestCalled = true;
    return _makeTseInfo();
  }

  @override
  Future<FiskalyTransaction> startTransaction({
    required String tseId,
    required String transactionId,
    required String clientId,
  }) async {
    startTransactionCalled = true;
    return const FiskalyTransaction(
      id: 'tx-id',
      transactionNumber: 1,
      state: 'ACTIVE',
    );
  }

  @override
  Future<FiskalyTransaction> finishTransaction({
    required String tseId,
    required String transactionId,
    required String clientId,
    required List<VatAmountPerRate> amountsPerVatRate,
    required String paymentType,
    required double paymentAmount,
    int txRevision = 2,
  }) async {
    finishTransactionCalled = true;
    return FiskalyTransaction(
      id: transactionId,
      transactionNumber: 1,
      state: 'FINISHED',
      signature: TseSignatureData(
        transactionNumber: 1,
        signatureCounter: 42,
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        signatureValue: 'base64sig==',
        tseSerialNumber: 'DEADBEEF',
        algorithm: 'ecdsa-plain-SHA384',
        publicKey: 'pubkey==',
        processType: 'Kassenbeleg-V1',
        processData: 'process-data',
      ),
    );
  }

  @override
  Future<ExportState> triggerExport(
    String tseId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      const ExportState(id: 'export-id', state: 'PENDING');
}

const _config = FiskalyConfig(
  apiKey: 'key',
  apiSecret: 'secret',
  tseId: 'tse-uuid',
  clientId: 'client-uuid',
  adminPin: '12345',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TseLifecycleService.initialize — full flow from CREATED', () {
    test('calls create, initialize, activate, registerClient', () async {
      final fake = _FakeFiskalyService(config: _config.copyWith());
      fake.setStateToReturn(TseState.created);

      final svc = TseLifecycleService(service: fake);
      final state =
          await svc.initialize(tseId: 'tse-uuid', clientId: 'client-uuid');

      expect(fake.createTseCalled, isTrue);
      expect(fake.initializeTseCalled, isTrue);
      expect(fake.activateTseCalled, isTrue);
      expect(fake.registerClientCalled, isTrue);
      expect(state.isReady, isTrue);
      expect(state.tseState, equals(TseState.active));
    });

    test('skips initialize/activate when already ACTIVE', () async {
      final fake = _FakeFiskalyService(config: _config.copyWith());
      fake.setStateToReturn(TseState.active);

      final svc = TseLifecycleService(service: fake);
      await svc.initialize(tseId: 'tse-uuid', clientId: 'client-uuid');

      expect(fake.initializeTseCalled, isFalse);
      expect(fake.activateTseCalled, isFalse);
      expect(fake.registerClientCalled, isTrue);
    });

    test('skips activate when already INITIALIZED', () async {
      final fake = _FakeFiskalyService(config: _config.copyWith());
      fake.setStateToReturn(TseState.initialized);

      final svc = TseLifecycleService(service: fake);
      await svc.initialize(tseId: 'tse-uuid', clientId: 'client-uuid');

      expect(fake.initializeTseCalled, isFalse);
      expect(fake.activateTseCalled, isTrue);
      expect(fake.registerClientCalled, isTrue);
    });
  });

  group('TseLifecycleService.getState', () {
    test('returns initial when no tseId configured', () async {
      final fake = _FakeFiskalyService(
        config: const FiskalyConfig(apiKey: 'k', apiSecret: 's'),
      );
      final svc = TseLifecycleService(service: fake);
      final state = await svc.getState();
      expect(state.tseState, equals(TseState.unknown));
    });

    test('returns fetched state when tseId configured', () async {
      final fake = _FakeFiskalyService(config: _config.copyWith());
      fake.setStateToReturn(TseState.active);
      final svc = TseLifecycleService(service: fake);
      final state = await svc.getState();
      expect(state.tseState, equals(TseState.active));
    });
  });

  group('TseLifecycleService.runSelfTest', () {
    test('calls runSelfTest and sets lastSelfTestAt', () async {
      final fake = _FakeFiskalyService(config: _config.copyWith());
      fake.setStateToReturn(TseState.active);
      final svc = TseLifecycleService(service: fake);
      final state = await svc.runSelfTest();
      expect(fake.runSelfTestCalled, isTrue);
      expect(state.lastSelfTestAt, isNotNull);
    });

    test('throws when tseId not configured', () async {
      final fake = _FakeFiskalyService(
        config: const FiskalyConfig(apiKey: 'k', apiSecret: 's'),
      );
      final svc = TseLifecycleService(service: fake);
      expect(
        () => svc.runSelfTest(),
        throwsA(isA<FiskalyException>()),
      );
    });
  });

  group('TseLifecycleService — transaction flow', () {
    test('startTransaction + finishTransaction returns signature', () async {
      final fake = _FakeFiskalyService(config: _config.copyWith());
      fake.setStateToReturn(TseState.active);
      final svc = TseLifecycleService(service: fake);

      await svc.startTransaction('tx-001');
      final finished = await svc.finishTransaction(
        transactionId: 'tx-001',
        amountsPerVatRate: [
          const VatAmountPerRate(
              vatRate: '19.00', incl: 23.80, excl: 20.00, vat: 3.80),
        ],
        paymentType: 'Bar',
        paymentAmount: 23.80,
      );

      expect(fake.startTransactionCalled, isTrue);
      expect(fake.finishTransactionCalled, isTrue);
      expect(finished.isFinished, isTrue);
      expect(finished.signature, isNotNull);
      expect(finished.signature!.signatureValue, equals('base64sig=='));
    });

    test('startTransaction throws when tseId not set', () async {
      final fake = _FakeFiskalyService(
        config: const FiskalyConfig(apiKey: 'k', apiSecret: 's'),
      );
      final svc = TseLifecycleService(service: fake);
      expect(
        () => svc.startTransaction('tx-001'),
        throwsA(isA<FiskalyException>()),
      );
    });
  });

  group('TseLifecycleState', () {
    test('isReady requires active + clientRegistered', () {
      const notReady = TseLifecycleState(
        tseState: TseState.initialized,
        isClientRegistered: true,
      );
      expect(notReady.isReady, isFalse);

      const noClient = TseLifecycleState(
        tseState: TseState.active,
        isClientRegistered: false,
      );
      expect(noClient.isReady, isFalse);

      const ready = TseLifecycleState(
        tseState: TseState.active,
        isClientRegistered: true,
      );
      expect(ready.isReady, isTrue);
    });
  });
}
