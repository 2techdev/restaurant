/// EcoCash V4.2 — single-sale state machine.
///
/// Caller invokes [start] with the bill total; the engine starts a sale,
/// polls `/api/get/transaction` every 500 ms and emits a
/// [CashCollectorTransaction] each tick so the UI can react. Polling
/// stops automatically when the transaction reaches a terminal state.
library;

import 'dart:async';
import 'dart:math';

import 'ecocash_client.dart';
import 'ecocash_models.dart';

class CashCollectorSaleEngine {
  CashCollectorSaleEngine(
    this.client, {
    this.pollInterval = const Duration(milliseconds: 500),
  });

  final EcoCashClient client;
  final Duration pollInterval;

  final _controller =
      StreamController<CashCollectorTransaction?>.broadcast();
  Timer? _timer;
  CashCollectorTransaction? _current;

  Stream<CashCollectorTransaction?> get transaction => _controller.stream;
  CashCollectorTransaction? get current => _current;

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }

  Future<void> start({
    required int saleAmount,
    required String currency,
    String? orderIdOverride,
  }) async {
    _cancelPolling();
    final orderId = orderIdOverride ?? _newOrderId();
    _emit(CashCollectorTransaction(
      orderId: orderId,
      saleAmount: saleAmount,
      currency: currency,
      state: CashCollectorState.starting,
    ));
    try {
      final started =
          await client.startSale(orderId: orderId, amount: saleAmount);
      _emit(_current!.copyWith(
        transId: started.transId,
        state: CashCollectorState.awaitingCash,
      ));
      _startPolling();
    } on EcoCashException catch (e) {
      _fail(e.toString());
    } catch (e) {
      _fail('startSale: $e');
    }
  }

  Future<void> cancel() async {
    _cancelPolling();
    final cur = _current;
    if (cur != null && cur.transId != null && !cur.isTerminal) {
      try {
        await client.cancelSale(orderId: cur.orderId, transId: cur.transId!);
      } catch (_) {
        // Best-effort. Operator may need to manually clear from kiosk.
      }
    }
    _emit(_current?.copyWith(state: CashCollectorState.cancelled));
  }

  void acknowledge() {
    _cancelPolling();
    _emit(null);
  }

  void _startPolling() {
    _timer = Timer.periodic(pollInterval, (_) async {
      final cur = _current;
      if (cur == null) {
        _cancelPolling();
        return;
      }
      try {
        final t = await client.getTransaction(orderId: cur.orderId);
        _apply(t);
        if (_current?.isTerminal ?? false) _cancelPolling();
      } on EcoCashException catch (e) {
        // 1106 = no info yet (sale just started). Keep polling.
        if (e.code != '1106') _fail(e.toString());
      } catch (_) {
        // Transient network error — keep polling.
      }
    });
  }

  void _apply(TransactionData t) {
    final prev = _current;
    if (prev == null) return;
    final state = switch (t.result) {
      1 => CashCollectorState.completed,
      2 => CashCollectorState.failed,
      _ when t.collectedAmount == 0 => CashCollectorState.awaitingCash,
      _ when t.collectedAmount < prev.saleAmount =>
        CashCollectorState.partial,
      _ when t.dispensedAmount > 0 => CashCollectorState.dispensingChange,
      _ => CashCollectorState.paidEnough,
    };
    _emit(prev.copyWith(
      transId: t.transId.isEmpty ? prev.transId : t.transId,
      collected: t.collectedAmount,
      dispensed: t.dispensedAmount,
      refund: t.refund,
      state: state,
      errorMessage: (t.result == 2 && t.refund > 0)
          ? 'Manual refund required: ${(t.refund / 100).toStringAsFixed(2)} ${prev.currency}'
          : null,
    ));
  }

  void _fail(String msg) {
    _emit(_current?.copyWith(
      state: CashCollectorState.failed,
      errorMessage: msg,
    ));
    _cancelPolling();
  }

  void _emit(CashCollectorTransaction? t) {
    _current = t;
    _controller.add(t);
  }

  void _cancelPolling() {
    _timer?.cancel();
    _timer = null;
  }

  static String _newOrderId() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${n.year}${p(n.month)}${p(n.day)}${p(n.hour)}${p(n.minute)}${p(n.second)}';
    final rnd =
        Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    return 'POS-$stamp-$rnd';
  }
}
