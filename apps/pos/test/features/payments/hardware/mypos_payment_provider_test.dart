import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/payment/config/mypos_config.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_method.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_request.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_status.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/mypos/mypos_client.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/mypos/mypos_payment_provider.dart';

// ---------------------------------------------------------------------------
// Fake client that bypasses MethodChannel
// ---------------------------------------------------------------------------

class FakeMyPosClient extends MyPosClient {
  FakeMyPosClient({
    required super.terminalIp,
    required super.terminalPort,
    this.connectSuccess = true,
    this.paymentResult,
    this.twintResult,
    this.refundResult,
  }) : _connected = connectSuccess;

  final bool connectSuccess;
  final MyPosPaymentResult? paymentResult;
  final MyPosPaymentResult? twintResult;
  final MyPosPaymentResult? refundResult;

  bool _connected;
  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect() async {
    _connected = connectSuccess;
    return connectSuccess;
  }

  @override
  Future<void> disconnect() async { _connected = false; }

  @override
  Future<MyPosPaymentResult> processPayment({
    required int amountCents,
    required String currency,
  }) async {
    return paymentResult ??
        const MyPosPaymentResult(
          success: true,
          transactionId: 'TXN-CARD',
          authCode: 'AUTH123',
          cardType: 'Visa',
          amountCents: 1000,
          currency: 'CHF',
        );
  }

  @override
  Future<MyPosPaymentResult> processTwintPayment({required int amountCents}) async {
    return twintResult ??
        const MyPosPaymentResult(
          success: true,
          transactionId: 'TXN-TWINT',
          cardType: 'TWINT',
          amountCents: 1000,
          currency: 'CHF',
        );
  }

  @override
  Future<MyPosPaymentResult> processRefund({
    required String transactionId,
    int? amountCents,
    String currency = 'CHF',
  }) async {
    return refundResult ??
        const MyPosPaymentResult(success: true, transactionId: 'TXN-REF');
  }

  @override
  Future<bool> cancelTransaction() async => true;

  @override
  Future<MyPosSettlementResult> endOfDay() async =>
      const MyPosSettlementResult(success: true, reportData: 'ok');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = MyPosConfig(terminalIp: '192.168.1.50', terminalPort: 60180);

  MyPosPaymentProvider buildProvider({
    bool connectSuccess = true,
    MyPosPaymentResult? paymentResult,
    MyPosPaymentResult? twintResult,
    MyPosPaymentResult? refundResult,
  }) {
    final client = FakeMyPosClient(
      terminalIp: config.terminalIp,
      terminalPort: config.terminalPort,
      connectSuccess: connectSuccess,
      paymentResult: paymentResult,
      twintResult: twintResult,
      refundResult: refundResult,
    );
    return MyPosPaymentProvider.withClient(config, client);
  }

  group('MyPosPaymentProvider — card', () {
    test('approved card payment', () async {
      final provider = buildProvider();

      const req = HardwarePaymentRequest(
        reference: 'TKT-001',
        amount: 10.00,
        currency: 'CHF',
        paymentMethod: HardwarePaymentMethod.card,
      );
      final result = await provider.processPayment(req);

      expect(result.isApproved, isTrue);
      expect(result.transactionId, equals('TXN-CARD'));
      expect(result.cardType, equals('Visa'));
    });

    test('declined card payment', () async {
      final provider = buildProvider(
        paymentResult: const MyPosPaymentResult(
          success: false,
          errorMessage: 'Insufficient funds',
        ),
      );

      const req = HardwarePaymentRequest(
        reference: 'TKT-002',
        amount: 99.99,
        currency: 'CHF',
      );
      final result = await provider.processPayment(req);

      expect(result.isDeclined, isTrue);
      expect(result.errorMessage, equals('Insufficient funds'));
    });
  });

  group('MyPosPaymentProvider — TWINT', () {
    test('approved TWINT payment (CHF)', () async {
      final provider = buildProvider();

      const req = HardwarePaymentRequest(
        reference: 'TKT-003',
        amount: 15.00,
        currency: 'CHF',
        paymentMethod: HardwarePaymentMethod.twint,
      );
      final result = await provider.processPayment(req);

      expect(result.isApproved, isTrue);
      expect(result.transactionId, equals('TXN-TWINT'));
      expect(result.cardType, equals('TWINT'));
      expect(result.currency, equals('CHF'));
    });

    test('TWINT rejected when currency is not CHF', () async {
      final provider = buildProvider();

      const req = HardwarePaymentRequest(
        reference: 'TKT-004',
        amount: 15.00,
        currency: 'EUR',
        paymentMethod: HardwarePaymentMethod.twint,
      );
      final result = await provider.processPayment(req);

      expect(result.status, equals(HardwarePaymentStatus.failed));
      expect(result.errorMessage, contains('CHF'));
    });
  });

  group('MyPosPaymentProvider — refund & cancel', () {
    test('successful refund', () async {
      final provider = buildProvider();
      final ok = await provider.refundPayment('TXN-CARD', amountCents: 1000);
      expect(ok, isTrue);
    });

    test('cancel returns true', () async {
      final provider = buildProvider();
      final ok = await provider.cancelPayment();
      expect(ok, isTrue);
    });
  });

  group('MyPosPaymentProvider — end of day', () {
    test('returns settlement data', () async {
      final provider = buildProvider();
      final data = await provider.endOfDay();
      expect(data['success'], isTrue);
    });
  });

  group('MyPosConfig', () {
    test('defaults', () {
      const c = MyPosConfig(terminalIp: '10.0.0.1');
      expect(c.terminalPort, equals(60180));
      expect(c.currency, equals('CHF'));
    });
  });
}
