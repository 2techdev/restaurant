import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/payment/interfaces/hardware_payment_provider.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_method.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_request.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_result.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_status.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/payment_engine.dart';

// ---------------------------------------------------------------------------
// Fake providers
// ---------------------------------------------------------------------------

class FakeProvider implements HardwarePaymentProvider {
  FakeProvider({
    required this.name,
    this.paymentResult,
    this.initError,
  });

  final String name;

  final HardwarePaymentResult? paymentResult;
  final Object? initError;

  bool _initialized = false;
  int initCallCount = 0;
  int paymentCallCount = 0;

  @override
  String get providerName => name;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    initCallCount++;
    if (initError != null) throw initError!;
    _initialized = true;
  }

  @override
  Future<HardwarePaymentResult> processPayment(HardwarePaymentRequest request) async {
    paymentCallCount++;
    return paymentResult ??
        HardwarePaymentResult.error(
          transactionId: request.reference,
          amount: request.amount,
          currency: request.currency,
          message: 'No result configured',
        );
  }

  @override
  Future<bool> refundPayment(String transactionId, {int? amountCents}) async => true;

  @override
  Future<bool> cancelPayment() async => true;

  @override
  Future<Map<String, dynamic>> endOfDay() async => {'success': true};

  @override
  Future<void> dispose() async { _initialized = false; }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const _request = HardwarePaymentRequest(
  reference: 'TICKET-001',
  amount: 25.50,
  currency: 'CHF',
  paymentMethod: HardwarePaymentMethod.card,
);

const _twintRequest = HardwarePaymentRequest(
  reference: 'TICKET-002',
  amount: 10.00,
  currency: 'CHF',
  paymentMethod: HardwarePaymentMethod.twint,
);

HardwarePaymentResult _approved(HardwarePaymentRequest req) =>
    HardwarePaymentResult(
      transactionId: 'TXN-OK',
      status: HardwarePaymentStatus.approved,
      amount: req.amount,
      currency: req.currency,
    );

HardwarePaymentResult _declined(HardwarePaymentRequest req) =>
    HardwarePaymentResult(
      transactionId: 'TXN-DEC',
      status: HardwarePaymentStatus.declined,
      amount: req.amount,
      currency: req.currency,
      errorMessage: 'Declined by issuer',
    );

HardwarePaymentResult _failed(HardwarePaymentRequest req) =>
    HardwarePaymentResult.error(
      transactionId: req.reference,
      amount: req.amount,
      currency: req.currency,
      message: 'Terminal connection lost',
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PaymentEngine — initialisation', () {
    test('initialises primary and fallback providers', () async {
      final primary = FakeProvider(name: 'Primary');
      final fallback = FakeProvider(name: 'Fallback');
      final engine = PaymentEngine(
        primaryProvider: primary,
        fallbackProvider: fallback,
      );

      await engine.initialize();

      expect(primary.initCallCount, equals(1));
      expect(fallback.initCallCount, equals(1));
      expect(engine.isInitialized, isTrue);
    });

    test('does not double-initialise same instance used as multiple roles', () async {
      final shared = FakeProvider(name: 'Shared');
      final engine = PaymentEngine(
        primaryProvider: shared,
        fallbackProvider: shared, // same instance
      );
      await engine.initialize();
      // Should only be initialised once
      expect(shared.initCallCount, equals(1));
    });
  });

  group('PaymentEngine — card routing', () {
    test('approved primary result is returned directly', () async {
      final primary = FakeProvider(
        name: 'Wallee',
        paymentResult: _approved(_request),
      );
      final engine = PaymentEngine(primaryProvider: primary);
      await engine.initialize();

      final result = await engine.processPayment(_request);

      expect(result.isApproved, isTrue);
      expect(primary.paymentCallCount, equals(1));
    });

    test('declined primary result is returned without trying fallback', () async {
      final primary = FakeProvider(
        name: 'Wallee',
        paymentResult: _declined(_request),
      );
      final fallback = FakeProvider(name: 'MyPOS');
      final engine = PaymentEngine(
        primaryProvider: primary,
        fallbackProvider: fallback,
      );
      await engine.initialize();

      final result = await engine.processPayment(_request);

      expect(result.isDeclined, isTrue);
      expect(fallback.paymentCallCount, equals(0));
    });

    test('failed primary falls back to fallback provider', () async {
      final primary = FakeProvider(
        name: 'Wallee',
        paymentResult: _failed(_request),
      );
      final fallback = FakeProvider(
        name: 'MyPOS',
        paymentResult: _approved(_request),
      );
      final engine = PaymentEngine(
        primaryProvider: primary,
        fallbackProvider: fallback,
      );
      await engine.initialize();

      final result = await engine.processPayment(_request);

      expect(result.isApproved, isTrue);
      expect(primary.paymentCallCount, equals(1));
      expect(fallback.paymentCallCount, equals(1));
    });

    test('failed primary with no fallback returns failed result', () async {
      final primary = FakeProvider(
        name: 'Wallee',
        paymentResult: _failed(_request),
      );
      final engine = PaymentEngine(primaryProvider: primary);
      await engine.initialize();

      final result = await engine.processPayment(_request);

      expect(result.isFailed, isTrue);
    });
  });

  group('PaymentEngine — TWINT routing', () {
    test('TWINT request goes to myposProvider', () async {
      final wallee = FakeProvider(name: 'Wallee');
      final mypos = FakeProvider(
        name: 'MyPOS',
        paymentResult: _approved(_twintRequest),
      );
      final engine = PaymentEngine(
        primaryProvider: wallee,
        myposProvider: mypos,
      );
      await engine.initialize();

      final result = await engine.processPayment(_twintRequest);

      expect(result.isApproved, isTrue);
      expect(wallee.paymentCallCount, equals(0));
      expect(mypos.paymentCallCount, equals(1));
    });

    test('TWINT falls back to primary when no myposProvider configured', () async {
      final primary = FakeProvider(
        name: 'Wallee',
        paymentResult: _approved(_twintRequest),
      );
      final engine = PaymentEngine(primaryProvider: primary);
      await engine.initialize();

      final result = await engine.processPayment(_twintRequest);

      expect(result.isApproved, isTrue);
      expect(primary.paymentCallCount, equals(1));
    });
  });

  group('PaymentEngine — end of day', () {
    test('collects results from all unique providers', () async {
      final primary = FakeProvider(name: 'Wallee');
      final mypos = FakeProvider(name: 'MyPOS');
      final engine = PaymentEngine(
        primaryProvider: primary,
        myposProvider: mypos,
      );
      await engine.initialize();

      final results = await engine.endOfDay();

      expect(results.containsKey('Wallee'), isTrue);
      expect(results.containsKey('MyPOS'), isTrue);
    });
  });

  group('PaymentEngine — dispose', () {
    test('disposes all providers', () async {
      final primary = FakeProvider(name: 'Wallee');
      final fallback = FakeProvider(name: 'MyPOS');
      final engine = PaymentEngine(
        primaryProvider: primary,
        fallbackProvider: fallback,
      );
      await engine.initialize();
      await engine.dispose();

      expect(primary.isInitialized, isFalse);
      expect(fallback.isInitialized, isFalse);
      expect(engine.isInitialized, isFalse);
    });
  });
}
