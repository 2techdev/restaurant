/// Payment screen — Kinetic Grid redesign for the fine-dining pilot.
///
/// Two-column layout:
///   LEFT  (flex 5)  Order summary — items + MWST breakdown + totals.
///   RIGHT (flex 7)  Method chips, tip chips, voucher/split, numpad, ÖDE.
///
/// Kinetic tokens: GcColors warm-light palette, zero-radius surfaces,
/// WorkSans/Inter type. Primary ÖDE button uses kPrimaryGradient.
///
/// On a successful payment the repository closes the ticket; the table
/// card turns green via its status-coloured provider.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';
import 'package:gastrocore_pos/features/audit_log/presentation/providers/audit_log_provider.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/customer_entity.dart';
import 'package:gastrocore_pos/features/customers/presentation/providers/customer_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/payments/domain/entities/payment_entity.dart';
import 'package:gastrocore_pos/features/payments/domain/entities/voucher_entity.dart';
import 'package:gastrocore_pos/features/payments/domain/mixed_tender_calculator.dart';
import 'package:gastrocore_pos/features/payments/presentation/providers/refund_provider.dart';
import 'package:gastrocore_pos/features/payments/presentation/widgets/cash_collector_dialog.dart';
import 'package:gastrocore_pos/features/payments/presentation/widgets/mypos_payment_dialog.dart';
import 'package:gastrocore_pos/features/payments/presentation/widgets/voucher_dialog.dart';
// TODO(printing-merge): re-enable these three imports once the `features/
// printing/*` files (currently untracked in the Cash Collector worktree)
// land on claude/pilot-final. They are required by `_autoPrintIfEnabled`
// and `_toReceiptItem` below, which are commented out in lockstep so this
// payment-redesign branch builds standalone. The redesign APK will not
// auto-print until that merge lands — manual print fallback on the
// receipt screen still works.
// import 'package:gastrocore_pos/features/printing/data/receipt_print_facade.dart';
// import 'package:gastrocore_pos/features/printing/domain/ch_receipt_renderer.dart';
// import 'package:gastrocore_pos/features/printing/printing_providers.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';

/// Local tender selection.
enum _Method { bar, karte, twint, gutschein }

class PaymentScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const PaymentScreen({super.key, required this.ticketId});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  _Method _method = _Method.bar;
  String _amountStr = ''; // Entered tendered amount (whole CHF for cash).
  int _tipAmount = 0; // In cents.
  int? _selectedTipPercent;
  VoucherEntity? _voucher;

  /// Running mixed-tender state. Stays empty in the common single-method
  /// flow; the list only grows when the cashier taps EKLE to stage a
  /// partial tender (e.g. CHF 20 cash toward a CHF 57 bill, rest card).
  MixedTenderCalculator _calc = const MixedTenderCalculator(grandTotalCents: 0);

  /// Staged loyalty redemption. Points are only debited from the customer
  /// (and the audit log emitted) on a successful payment; cancelling the
  /// screen before PAY leaves the balance untouched. 1 point == 1 cent.
  int _loyaltyPointsToRedeem = 0;

  /// Customer linked to the current ticket, loaded once after the ticket
  /// arrives. Null when the ticket has no linked customer.
  CustomerEntity? _linkedCustomer;
  String? _customerLoadedFor; // ticket.customerId we already fetched for

  bool _paymentComplete = false;
  bool _submitting = false;

  /// Result from the Cash Collector kiosk for the cash leg of this sale.
  /// Non-null only when the operator picked BAR with the collector enabled
  /// AND the device successfully accepted cash. We hold it so the change
  /// indicator and completion view show what the device actually dispensed.
  CashCollectorResult? _cashCollectorResult;

  /// One-shot escape hatch: when the operator hit "Manuel girişe geç" in
  /// the Cash Collector dialog, we unhide the numpad for *this* ticket so
  /// they can finish manually. Doesn't touch the saved toggle — the next
  /// ticket re-attempts the device.
  bool _cashCollectorBypassed = false;

  /// MyPOS terminal result for the card / TWINT leg of this sale. Non-null
  /// once the terminal has approved the payment. Drives the receipt
  /// reference (transaction id, auth code, card type) and prevents
  /// double-submitting.
  MyPosPaymentResult? _myposResult;

  /// One-shot bypass when the operator picks "Manuel'e geç" in the MyPOS
  /// dialog. Restores the numpad/legacy flow for the current ticket only.
  bool _myposBypassed = false;

  TicketEntity? _ticket;

  // --- Derived totals ------------------------------------------------------

  int get _subtotal => _ticket?.subtotal ?? 0;
  int get _taxAmount => _ticket?.taxAmount ?? 0;
  int get _baseTotal => _ticket?.total ?? 0;
  int get _voucherDiscount => _voucher?.discountAmount ?? 0;

  /// Loyalty discount in cents. Points redeem 1:1 as cents
  /// (100 points = CHF 1.00).
  int get _loyaltyDiscount => _loyaltyPointsToRedeem;

  int get _grandTotal {
    final total =
        _baseTotal + _tipAmount - _voucherDiscount - _loyaltyDiscount;
    return total < 0 ? 0 : total;
  }

  /// Outstanding balance when at least one tender has been staged.
  /// Falls back to the grand total for the empty-list flow so the
  /// existing single-method UX keeps working unchanged.
  int get _outstanding {
    if (!_calc.hasTenders) return _grandTotal;
    return _liveCalc.outstandingCents;
  }

  /// Calculator kept in lockstep with the live grand total so tip /
  /// voucher / loyalty changes after the first tender don't leave the
  /// outstanding balance stale.
  MixedTenderCalculator get _liveCalc =>
      _calc.withGrandTotal(_grandTotal);

  PaymentMethod _domainMethodFor(_Method m) {
    return switch (m) {
      _Method.bar => PaymentMethod.cash,
      _Method.karte => PaymentMethod.creditCard,
      _Method.twint => PaymentMethod.other,
      _Method.gutschein => PaymentMethod.other,
    };
  }

  String? _referenceFor(_Method m) {
    // MyPOS approval overrides the static label for the terminal-driven
    // methods so the receipt / audit row carries the SDK transaction id
    // and the card type (or "TWINT") right after the prefix.
    if (_myposResult != null &&
        (m == _Method.karte || m == _Method.twint)) {
      final r = _myposResult!;
      final tag = m == _Method.twint
          ? 'MYPOS:TWINT'
          : 'MYPOS:${r.cardType ?? "CARD"}';
      return '$tag:${r.transactionId}';
    }
    return switch (m) {
      _Method.twint => 'TWINT',
      _Method.gutschein =>
        _voucher != null ? 'VOUCHER:${_voucher!.code}' : 'GUTSCHEIN',
      _ when _voucher != null => 'VOUCHER:${_voucher!.code}',
      _ => null,
    };
  }

  /// Map a persisted tender entry back to a UI method enum for the strip
  /// label. Twint/Gutschein share PaymentMethod.other so we disambiguate
  /// via the reference.
  _Method _uiMethodFor(TenderEntry t) {
    if (t.method == PaymentMethod.cash) return _Method.bar;
    if (t.method == PaymentMethod.creditCard ||
        t.method == PaymentMethod.debitCard) {
      return _Method.karte;
    }
    if (t.reference == 'TWINT') return _Method.twint;
    return _Method.gutschein;
  }

  /// Maximum points that can be redeemed on this ticket: capped by the
  /// customer's balance and by the ticket total (we never allow the bill
  /// to go negative via puan).
  int get _maxRedeemablePoints {
    final customer = _linkedCustomer;
    if (customer == null) return 0;
    final billRoom = _baseTotal + _tipAmount - _voucherDiscount;
    if (billRoom <= 0) return 0;
    return customer.loyaltyPoints < billRoom
        ? customer.loyaltyPoints
        : billRoom;
  }

  List<OrderItemEntity> get _items => _ticket?.items ?? const [];

  int get _enteredCents {
    if (_amountStr.isEmpty) return 0;
    final value = int.tryParse(_amountStr) ?? 0;
    return value * 100;
  }

  int get _changeAmount {
    if (_method != _Method.bar) return 0;
    // Cash Collector path: the device computed and dispensed change for us.
    if (_cashCollectorResult != null) return _cashCollectorResult!.dispensed;
    final target = _outstanding;
    if (_enteredCents <= target) return 0;
    return _enteredCents - target;
  }

  /// True when the cash leg of this ticket should route through the
  /// EcoCash kiosk: setting on, BAR selected, and the operator hasn't
  /// punched the manual-bypass button for this ticket.
  bool get _cashCollectorActive {
    if (_method != _Method.bar) return false;
    if (_cashCollectorBypassed) return false;
    final collector =
        ref.read(paymentSettingsProvider).valueOrNull?.cashCollector;
    return collector?.enabled == true;
  }

  /// True when KART (and likewise TWINT) should hand off to the MyPOS
  /// Sigma terminal: setting on, method is KART or TWINT, and operator
  /// hasn't bypassed for this ticket.
  bool get _myposActive {
    if (_method != _Method.karte && _method != _Method.twint) return false;
    if (_myposBypassed) return false;
    final mypos = ref.read(paymentSettingsProvider).valueOrNull?.mypos;
    return mypos?.enabled == true;
  }

  bool get _canPay {
    if (_submitting || _grandTotal <= 0) return false;
    if (_calc.hasTenders && _liveCalc.isFullyPaid) return true;
    final target = _outstanding;
    if (_method == _Method.bar) {
      // When the Cash Collector is wired up, the operator doesn't have to
      // pre-enter the tendered amount on the numpad — the kiosk collects
      // it from the customer directly.
      if (_cashCollectorActive) return true;
      return _enteredCents >= target;
    }
    // KART / TWINT via MyPOS: terminal owns the amount, no numpad needed.
    if (_myposActive) return true;
    return true; // Non-cash methods assume exact-outstanding tender.
  }

  /// Whether the "+ EKLE" (stage partial) button should be enabled.
  ///
  /// Active whenever the cashier has entered a non-zero amount that's
  /// still below the outstanding balance. Covers mixed-method flows:
  /// CHF 20 cash + card, or CHF 30 card + TWINT, etc.
  bool get _canStage {
    if (_submitting || _grandTotal <= 0) return false;
    if (_calc.hasTenders && _liveCalc.isFullyPaid) return false;
    final target = _outstanding;
    if (target <= 0) return false;
    return _enteredCents > 0 && _enteredCents < target;
  }

  String _fmt(int cents) {
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return 'CHF ${whole.toString()}.$frac';
  }

  // --- Inputs --------------------------------------------------------------

  void _onDigit(String digit) {
    if (_amountStr.length >= 6) return;
    setState(() => _amountStr = (_amountStr + digit));
  }

  void _onBackspace() {
    if (_amountStr.isEmpty) return;
    setState(() => _amountStr = _amountStr.substring(0, _amountStr.length - 1));
  }

  void _onClear() => setState(() => _amountStr = '');

  void _applyTipPercent(int percent) {
    final cents = (_baseTotal * percent / 100).round();
    setState(() {
      _selectedTipPercent = percent;
      _tipAmount = cents;
    });
  }

  void _clearTip() {
    setState(() {
      _selectedTipPercent = null;
      _tipAmount = 0;
    });
  }

  Future<void> _customTipDialog() async {
    final controller = TextEditingController(
      text: _tipAmount > 0 ? (_tipAmount / 100).toStringAsFixed(2) : '',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GcColors.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: GcColors.outlineVariant),
        ),
        title: const Text('Trinkgeld (CHF)', style: GcText.headline),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: const InputDecoration(hintText: '0.00'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text) ?? 0;
              Navigator.of(ctx).pop((value * 100).round());
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() {
        _selectedTipPercent = null;
        _tipAmount = result;
      });
    }
  }

  Future<void> _pickVoucher() async {
    final voucher = await showVoucherDialog(context);
    if (voucher != null) setState(() => _voucher = voucher);
  }

  void _clearVoucher() => setState(() => _voucher = null);

  // --- Loyalty redemption --------------------------------------------------

  /// Resolve the customer entity once per ticket.customerId change. We don't
  /// want to refetch on every rebuild, so we cache by the id we loaded for.
  Future<void> _maybeLoadLinkedCustomer(String? customerId) async {
    if (customerId == _customerLoadedFor) return;
    _customerLoadedFor = customerId;
    if (customerId == null) {
      setState(() {
        _linkedCustomer = null;
        _loyaltyPointsToRedeem = 0;
      });
      return;
    }
    try {
      final repo = ref.read(customerRepositoryProvider);
      final c = await repo.getCustomerById(customerId);
      if (!mounted) return;
      setState(() {
        _linkedCustomer = c;
        // If the balance dropped below what we had staged, clamp.
        if (c != null && _loyaltyPointsToRedeem > c.loyaltyPoints) {
          _loyaltyPointsToRedeem = c.loyaltyPoints;
        }
      });
    } catch (_) {
      // Non-fatal: we just won't render the puan affordance.
    }
  }

  void _clearLoyalty() => setState(() => _loyaltyPointsToRedeem = 0);

  Future<void> _openLoyaltyDialog() async {
    final customer = _linkedCustomer;
    if (customer == null) return;
    final maxPoints = _maxRedeemablePoints;
    if (maxPoints <= 0) return;

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => _LoyaltyRedeemDialog(
        balance: customer.loyaltyPoints,
        maxRedeemable: maxPoints,
        initial: _loyaltyPointsToRedeem,
      ),
    );
    if (result != null && mounted) {
      setState(() => _loyaltyPointsToRedeem = result.clamp(0, maxPoints));
    }
  }

  // --- Payment -------------------------------------------------------------

  Future<void> _submit() async {
    if (!_canPay) return;

    // MyPOS terminal intercept — when KART or TWINT is selected and the
    // Sigma terminal is enabled, hand the leg straight to the device. The
    // dialog blocks until the terminal returns an approval / decline; on
    // fallback we drop back to the manual flow for this ticket.
    if (_myposActive) {
      final myposCfg = ref.read(paymentSettingsProvider).valueOrNull!.mypos;
      final outstanding = _outstanding > 0 ? _outstanding : _grandTotal;
      final flow = _method == _Method.twint ? MyPosFlow.twint : MyPosFlow.card;
      final result = await showMyPosPaymentDialog(
        context,
        config: myposCfg,
        amountCents: outstanding,
        flow: flow,
      );
      if (!mounted) return;
      if (result == null) return; // operator cancelled, terminal idle
      if (result.fallbackToManual) {
        setState(() {
          _myposBypassed = true;
          _amountStr = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Manuel ödeme kaydına geçildi.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      if (!result.approved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Terminal reddetti: ${result.errorMessage ?? "bilinmeyen hata"}',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }
      setState(() => _myposResult = result);
    }

    // Cash Collector intercept — when the operator picked BAR and the kiosk
    // is enabled in Settings, hand the cash leg to the device. The dialog
    // returns the actual collected/dispensed amounts on success, or null if
    // the operator cancelled before any cash was accepted (in which case we
    // abort the whole _submit so they can pick another tender).
    if (_cashCollectorActive) {
      final paymentSettings = ref.read(paymentSettingsProvider).valueOrNull;
      final collectorCfg = paymentSettings!.cashCollector;
      final outstanding = _outstanding > 0 ? _outstanding : _grandTotal;
      final result = await showCashCollectorDialog(
        context,
        config: collectorCfg,
        saleAmountCents: outstanding,
      );
      if (!mounted) return;
      if (result == null) return; // cancelled
      if (result.fallbackToManual) {
        // Bypass the device for this ticket only — show the numpad and
        // let the operator finish manually. The toggle in Settings stays
        // on, so the next ticket retries the kiosk.
        setState(() {
          _cashCollectorBypassed = true;
          _amountStr = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Manuel nakit girişine geçildi.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      setState(() => _cashCollectorResult = result);
      if (result.refund > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cihaz ${(result.refund / 100).toStringAsFixed(2)} CHF '
              'iade veremedi — elden geri verin.',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }

    setState(() => _submitting = true);

    final tenantId = ref.read(tenantIdProvider);
    final currentUser = ref.read(currentUserProvider);
    final receivedBy = currentUser?.name ?? 'POS';

    // Build the final tender list. When the cashier staged partials via
    // EKLE we process them in order; otherwise we fall through to the
    // single-tender path identical to the pre-mixed flow.
    final tenders = _buildFinalTenders();

    try {
      // Debit loyalty points first — if that fails the payment should NOT
      // be written. The customer repo throws "Insufficient points" if the
      // balance is stale; catching forces the cashier to re-check the chip.
      final customer = _linkedCustomer;
      final redeemed = _loyaltyPointsToRedeem;
      if (customer != null && redeemed > 0) {
        await ref.read(customerRepositoryProvider).redeemPoints(
              customer.id,
              points: redeemed,
              orderId: widget.ticketId,
            );
        ref.invalidate(customerByIdProvider(customer.id));

        final audit = ref.read(auditServiceProvider);
        unawaited(
          audit.log(
            action: AuditAction.loyaltyRedeemed,
            entityType: 'customer',
            entityId: customer.id,
            newValueJson:
                '{"points":$redeemed,"orderId":"${widget.ticketId}","discountCents":$redeemed}',
            reason: '${customer.name} · $redeemed puan',
          ),
        );
      }

      final paymentRepo = ref.read(paymentRepositoryProvider);
      // Apply the whole tip to the FINAL tender so it isn't multiplied
      // across rows. Sum of `amount` across rows equals grand total
      // (tip already included in grand total). Tendered amount equals
      // the row's contribution except for the final cash row where we
      // pass the raw cash handed over so change can be computed.
      for (int i = 0; i < tenders.length; i++) {
        final t = tenders[i];
        final isLast = i == tenders.length - 1;
        final tip = isLast ? _tipAmount : 0;
        await paymentRepo.processPayment(
          ticketId: widget.ticketId,
          tenantId: tenantId,
          paymentMethod: t.method,
          amount: t.amountCents,
          tipAmount: tip,
          tenderedAmount: t.amountCents,
          receivedBy: receivedBy,
          reference: t.reference,
        );
      }

      ref.read(currentTicketProvider.notifier).clear();
      if (!mounted) return;
      setState(() => _paymentComplete = true);

      // TODO(printing-merge): re-enable auto-print once the printing/
      // feature lands on claude/pilot-final. The receipt screen still
      // surfaces a manual print button so this regression is recoverable.
      // unawaited(_autoPrintIfEnabled(receivedBy: receivedBy));

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) context.go(AppRoutes.receiptFor(widget.ticketId));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ödeme hatası: $e')),
      );
    }
  }

  // TODO(printing-merge): restore `_autoPrintIfEnabled` and `_toReceiptItem`
  // once the printing/ feature lands on claude/pilot-final. They were
  // commented out so this payment-redesign branch builds standalone — the
  // imports they rely on (receipt_print_facade.dart, ch_receipt_renderer.
  // dart, printing_providers.dart) only exist as untracked files in the
  // Cash Collector worktree at the time this branch was cut.
  //
  // Full original implementations are preserved in git history at:
  //   git log claude/pos-payment-redesign-20260513^ -- apps/pos/lib/features/
  //   payments/presentation/screens/payment_screen.dart
  // Restoration is a straight un-comment of both methods + the three
  // imports above + the `unawaited(_autoPrintIfEnabled(...))` line in
  // `_submit`. No signature changes.

  /// Resolve the tender list that will actually hit the repository.
  ///
  /// Two shapes exist:
  ///   * Mixed flow — cashier staged some tenders via EKLE. If the bill
  ///     is already fully paid by the staged list, use it as-is; if
  ///     there's outstanding balance, append one final tender using the
  ///     currently selected method + entered (or outstanding) amount.
  ///   * Single flow — tenders list empty: emit one entry matching the
  ///     current method/amount.
  List<TenderEntry> _buildFinalTenders() {
    final live = _liveCalc;
    if (_calc.hasTenders) {
      if (live.isFullyPaid) return List<TenderEntry>.from(live.tenders);
      final outstanding = live.outstandingCents;
      final method = _domainMethodFor(_method);
      final amount = _method == _Method.bar
          ? (_enteredCents > outstanding ? outstanding : _enteredCents)
          : outstanding;
      return [
        ...live.tenders,
        TenderEntry(
          method: method,
          amountCents: amount,
          reference: _referenceFor(_method),
        ),
      ];
    }
    final method = _domainMethodFor(_method);
    final amount = _method == _Method.bar
        ? (_enteredCents > _grandTotal ? _grandTotal : _enteredCents)
        : _grandTotal;
    return [
      TenderEntry(
        method: method,
        amountCents: amount,
        reference: _referenceFor(_method),
      ),
    ];
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen(ticketByIdProvider(widget.ticketId), (_, next) {
      next.whenData((t) {
        if (t != null && mounted) {
          setState(() => _ticket = t);
          _maybeLoadLinkedCustomer(t.customerId);
        }
      });
    });

    if (_paymentComplete) return _buildCompletion();

    if (_ticket == null) {
      return const Scaffold(
        backgroundColor: GcColors.surface,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: GcColors.surface,
      appBar: AppBar(
        backgroundColor: GcColors.surface,
        foregroundColor: GcColors.onSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'ÖDEME · ${_ticket!.orderNumber}'.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'WorkSans',
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppTokens.space16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: _buildSummary()),
            const SizedBox(width: AppTokens.space16),
            Expanded(flex: 7, child: _buildPaymentSide()),
          ],
        ),
      ),
    );
  }

  // --- LEFT — Summary ------------------------------------------------------

  Widget _buildSummary() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: GcColors.surfaceContainerLowest,
        border: Border.fromBorderSide(
          BorderSide(color: GcColors.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.space16,
              vertical: AppTokens.space12,
            ),
            color: GcColors.surfaceContainerLow,
            child: Row(
              children: [
                const Icon(
                  Icons.receipt_long_rounded,
                  size: 18,
                  color: GcColors.onSurfaceVariant,
                ),
                const SizedBox(width: AppTokens.space8),
                Text(
                  'ADİSYON · ${_items.length} KALEM',
                  style: const TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: GcColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.space4),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: GcColors.outlineVariant,
              ),
              itemBuilder: (_, i) {
                final item = _items[i];
                final isIkram = item.subtotal == 0 ||
                    (item.notes ?? '').startsWith('[İKRAM]');
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.space16,
                    vertical: AppTokens.space8,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${item.quantity.toStringAsFixed(0)}×',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: GcColors.onSurface,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              style: const TextStyle(
                                fontFamily: 'WorkSans',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: GcColors.onSurface,
                              ),
                            ),
                            if (isIkram)
                              const Text(
                                'İKRAM',
                                style: TextStyle(
                                  fontFamily: 'WorkSans',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: GcColors.tertiary,
                                  letterSpacing: 1.0,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        _fmt(item.subtotal),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: GcColors.onSurface,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.space16,
              vertical: AppTokens.space12,
            ),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: GcColors.outlineVariant),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _totalLine('Ara Toplam', _fmt(_subtotal - _taxAmount)),
                _totalLine('MWST (8.1%)', _fmt(_taxAmount)),
                if (_tipAmount > 0)
                  _totalLine(
                    'Trinkgeld',
                    '+${_fmt(_tipAmount)}',
                    valueColor: GcColors.secondary,
                  ),
                if (_voucher != null)
                  _totalLine(
                    'Gutschein (${_voucher!.code})',
                    '-${_fmt(_voucherDiscount)}',
                    valueColor: GcColors.tertiary,
                  ),
                if (_loyaltyPointsToRedeem > 0)
                  _totalLine(
                    'Puan (${_loyaltyPointsToRedeem}P)',
                    '-${_fmt(_loyaltyDiscount)}',
                    valueColor: GcColors.tertiary,
                  ),
                const SizedBox(height: AppTokens.space8),
                const Divider(color: GcColors.outlineVariant, height: 1),
                const SizedBox(height: AppTokens.space8),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'TOPLAM',
                        style: TextStyle(
                          fontFamily: 'WorkSans',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: GcColors.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      _fmt(_grandTotal),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: GcColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalLine(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: GcColors.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor ?? GcColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // --- RIGHT — Payment -----------------------------------------------------

  Widget _buildPaymentSide() {
    final showLoyalty = _linkedCustomer != null;
    final showTenders = _calc.hasTenders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _methodRow(),
        if (showLoyalty) ...[
          const SizedBox(height: AppTokens.space12),
          _loyaltyRow(),
        ],
        const SizedBox(height: AppTokens.space12),
        _tipRow(),
        const SizedBox(height: AppTokens.space12),
        _extraRow(),
        if (showTenders) ...[
          const SizedBox(height: AppTokens.space12),
          _buildTenderStrip(),
        ],
        const SizedBox(height: AppTokens.space12),
        Expanded(child: _buildMethodBody()),
        const SizedBox(height: AppTokens.space12),
        _buildPayCta(),
      ],
    );
  }

  Widget _loyaltyRow() {
    final customer = _linkedCustomer!;
    final hasRedemption = _loyaltyPointsToRedeem > 0;
    final maxPoints = _maxRedeemablePoints;
    final canRedeem = maxPoints > 0;

    return Container(
      padding: const EdgeInsets.all(AppTokens.space8),
      decoration: BoxDecoration(
        color: hasRedemption
            ? GcColors.tertiary.withValues(alpha: 0.08)
            : GcColors.surfaceContainerLowest,
        border: Border.all(
          color: hasRedemption
              ? GcColors.tertiary
              : GcColors.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppTokens.space8),
            child: Icon(
              Icons.stars_rounded,
              size: 18,
              color: GcColors.tertiary,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PUAN · ${customer.name.toUpperCase()}',
                  style: const TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: GcColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasRedemption
                      ? '${_loyaltyPointsToRedeem}P uygulandı · ${_fmt(_loyaltyDiscount)} indirim'
                      : 'Mevcut ${customer.loyaltyPoints}P · en fazla ${maxPoints}P kullanılabilir',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: GcColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (hasRedemption) ...[
            TextButton(
              onPressed: _clearLoyalty,
              child: const Text('KALDIR'),
            ),
            const SizedBox(width: AppTokens.space4),
          ],
          FilledButton(
            onPressed: canRedeem ? _openLoyaltyDialog : null,
            style: FilledButton.styleFrom(
              backgroundColor: GcColors.tertiary,
              foregroundColor: GcColors.onPrimary,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Text(hasRedemption ? 'DEĞİŞTİR' : 'KULLAN'),
          ),
        ],
      ),
    );
  }

  Widget _methodRow() {
    return SizedBox(
      height: AppTokens.touchLarge,
      child: Row(
        children: [
          _methodChip(_Method.bar, Icons.payments_rounded, 'BAR'),
          const SizedBox(width: AppTokens.space8),
          _methodChip(_Method.karte, Icons.credit_card_rounded, 'KARTE'),
          const SizedBox(width: AppTokens.space8),
          _methodChip(_Method.twint, Icons.phone_iphone_rounded, 'TWINT'),
          const SizedBox(width: AppTokens.space8),
          _methodChip(
            _Method.gutschein,
            Icons.confirmation_number_rounded,
            'GUTSCHEIN',
          ),
        ],
      ),
    );
  }

  Widget _methodChip(_Method m, IconData icon, String label) {
    final selected = _method == m;
    return Expanded(
      child: Material(
        color: selected
            ? GcColors.primary
            : GcColors.surfaceContainerLowest,
        child: InkWell(
          onTap: () => setState(() {
            _method = m;
            // Switching methods clears the one-shot manual bypass so a
            // KARTE→BAR roundtrip re-arms the Cash Collector / MyPOS flow.
            if (m == _Method.bar) _cashCollectorBypassed = false;
            if (m == _Method.karte || m == _Method.twint) {
              _myposBypassed = false;
            }
          }),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: selected ? kPrimaryGradient : null,
              border: Border.all(
                color: selected ? GcColors.primary : GcColors.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? GcColors.onPrimary : GcColors.onSurface,
                ),
                const SizedBox(width: AppTokens.space8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: selected ? GcColors.onPrimary : GcColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tipRow() {
    final hasTip = _tipAmount > 0;
    return Container(
      padding: const EdgeInsets.all(AppTokens.space8),
      decoration: BoxDecoration(
        color: GcColors.surfaceContainerLowest,
        border: Border.all(color: GcColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppTokens.space8),
                child: Text(
                  'TRINKGELD',
                  style: TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: GcColors.onSurfaceVariant,
                  ),
                ),
              ),
              _tipChip('0%', _tipAmount == 0, _clearTip),
              const SizedBox(width: AppTokens.space4),
              _tipChip('5%', _selectedTipPercent == 5,
                  () => _applyTipPercent(5)),
              const SizedBox(width: AppTokens.space4),
              _tipChip(
                '10%',
                _selectedTipPercent == 10,
                () => _applyTipPercent(10),
              ),
              const SizedBox(width: AppTokens.space4),
              _tipChip(
                '15%',
                _selectedTipPercent == 15,
                () => _applyTipPercent(15),
              ),
              const SizedBox(width: AppTokens.space4),
              _tipChip(
                _tipAmount > 0 && _selectedTipPercent == null
                    ? '${_fmt(_tipAmount).replaceFirst("CHF ", "")} CHF'
                    : 'ÖZEL',
                _selectedTipPercent == null && _tipAmount > 0,
                _customTipDialog,
              ),
            ],
          ),
          // v2 live preview — binds the tip selection back to the grand
          // total so operators don't have to reconcile it against the
          // left-panel summary in their head. Even at 0% we show the
          // grand total here for symmetry (the row becomes the right-
          // panel's "running total" line).
          const SizedBox(height: 6),
          const Divider(color: GcColors.outlineVariant, height: 1),
          const SizedBox(height: 6),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppTokens.space8),
            child: Row(
              children: [
                Icon(
                  hasTip
                      ? Icons.trending_up_rounded
                      : Icons.horizontal_rule_rounded,
                  size: 14,
                  color: hasTip
                      ? GcColors.secondary
                      : GcColors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  hasTip
                      ? '+${_fmt(_tipAmount)} '
                          '(${_selectedTipPercent != null ? "$_selectedTipPercent%" : "ÖZEL"})'
                      : 'Trinkgeld yok',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: hasTip
                        ? GcColors.secondary
                        : GcColors.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                const Text(
                  'TOPLAM',
                  style: TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: GcColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _fmt(_grandTotal),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: GcColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipChip(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: selected ? GcColors.primary : GcColors.surfaceContainerLow,
            border: Border.all(
              color: selected ? GcColors.primary : GcColors.outlineVariant,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? GcColors.onPrimary : GcColors.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  /// v2: BÖL moved next to ÖDE in the CTA row; this row is now the
  /// voucher affordance only so the GUTSCHEIN chip can span the width
  /// and the voucher code stays readable.
  Widget _extraRow() {
    return _extraButton(
      icon: Icons.card_giftcard_rounded,
      label: _voucher == null
          ? 'GUTSCHEIN'
          : 'GUTSCHEIN · ${_voucher!.code}',
      onTap: _voucher == null ? _pickVoucher : _clearVoucher,
      active: _voucher != null,
    );
  }

  Widget _extraButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return SizedBox(
      height: 44,
      child: Material(
        color: active
            ? GcColors.tertiary
            : GcColors.surfaceContainerLowest,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: active ? GcColors.tertiary : GcColors.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: active ? GcColors.onPrimary : GcColors.onSurface,
                ),
                const SizedBox(width: AppTokens.space8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: active ? GcColors.onPrimary : GcColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMethodBody() {
    // Always show the numpad — for non-cash methods the entered amount
    // represents an optional *partial* tender (e.g. CHF 30 on card).
    // Leaving the numpad empty means "pay the full outstanding via this
    // method", which keeps the single-tap UX for the common case.
    if (_method == _Method.bar) {
      // Cash Collector active: the kiosk handles the money — no need for
      // the numpad. Show a banner that explains the flow and points at
      // the ÖDE button.
      if (_cashCollectorActive) return _buildCollectorBanner();
      return _buildNumpad();
    }
    // KART / TWINT via MyPOS: the terminal owns the amount and the UI.
    // The numpad would be misleading (partial tendering isn't supported
    // by the device for these flows), so we hide it and show the banner.
    if (_myposActive) return _buildMyPosBanner();
    return Column(
      children: [
        _buildTerminalBanner(),
        const SizedBox(height: AppTokens.space8),
        Expanded(child: _buildNumpad()),
      ],
    );
  }

  /// Live-status card shown in place of the numpad when the MyPOS terminal
  /// is wired up. Redesign v2: the amount due is the visual anchor (big
  /// figure, centred), with a small status pill near the icon and the
  /// manual fallback reduced to a one-line text link near the bottom so
  /// it stops competing with the primary ÖDE button for attention.
  Widget _buildMyPosBanner() {
    final isTwint = _method == _Method.twint;
    final headline = isTwint ? 'TWINT TERMİNALİ HAZIR' : 'KART TERMİNALİ HAZIR';
    final hint = isTwint
        ? 'ÖDE’ye basın · terminal QR’ı gösterecek · müşteri okutsun.'
        : 'ÖDE’ye basın · terminal kart bekleyecek · yaklaştır / tak + PIN.';
    return _LiveStatusCard(
      icon: isTwint ? Icons.qr_code_2_rounded : Icons.credit_card_rounded,
      headline: headline,
      statusLabel: 'TERMİNAL · HAZIR',
      amountLabel: 'BEKLENEN',
      amountFormatted: _fmt(_outstanding),
      hint: hint,
      manualLinkLabel: 'manuel’e geç',
      onManual: _submitting
          ? null
          : () => setState(() {
                _myposBypassed = true;
                _amountStr = '';
              }),
    );
  }

  /// Live-status card shown in place of the cash numpad when the EcoCash
  /// kiosk is wired up. v2: same layout language as MyPOS banner so
  /// operators learn one pattern. ÖDE remains the only primary action.
  Widget _buildCollectorBanner() {
    return _LiveStatusCard(
      icon: Icons.savings_rounded,
      headline: 'KASA OTOMATI HAZIR',
      statusLabel: 'CİHAZ · HAZIR',
      amountLabel: 'ALINACAK',
      amountFormatted: _fmt(_outstanding),
      hint: 'ÖDE’ye basın · cihaz parayı alacak · para üstünü otomatik verecek.',
      manualLinkLabel: 'manuel girişe geç',
      onManual: _submitting
          ? null
          : () => setState(() {
                _cashCollectorBypassed = true;
                _amountStr = '';
              }),
    );
  }

  /// Compact banner shown above the numpad for non-cash methods. Tells
  /// the cashier which terminal to use while keeping the numpad visible
  /// so partial tenders can be staged.
  Widget _buildTerminalBanner() {
    final label = switch (_method) {
      _Method.karte => 'KARTENTERMINAL',
      _Method.twint => 'TWINT',
      _Method.gutschein => 'GUTSCHEIN',
      _Method.bar => '',
    };
    final icon = switch (_method) {
      _Method.karte => Icons.credit_card_rounded,
      _Method.twint => Icons.phone_iphone_rounded,
      _Method.gutschein => Icons.confirmation_number_rounded,
      _Method.bar => Icons.payments_rounded,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space16,
        vertical: AppTokens.space8,
      ),
      decoration: BoxDecoration(
        color: GcColors.surfaceContainerLow,
        border: Border.all(color: GcColors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: GcColors.onSurfaceVariant),
          const SizedBox(width: AppTokens.space8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'WorkSans',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: GcColors.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            _amountStr.isEmpty
                ? 'Tam ödeme: ${_fmt(_outstanding)}'
                : 'Kısmi: ${_fmt(_enteredCents)}',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: GcColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // --- Cash numpad ---------------------------------------------------------

  Widget _buildNumpad() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: GcColors.surfaceContainerLowest,
        border: Border.all(color: GcColors.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppTokens.space16),
            color: GcColors.surfaceContainerLow,
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'ALINAN (CHF)',
                    style: TextStyle(
                      fontFamily: 'WorkSans',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: GcColors.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  _amountStr.isEmpty ? '0' : _amountStr,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: GcColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (_changeAmount > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.space16,
                vertical: AppTokens.space8,
              ),
              color: GcColors.secondaryDim,
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'RÜCKGELD',
                      style: TextStyle(
                        fontFamily: 'WorkSans',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: GcColors.onSecondary,
                      ),
                    ),
                  ),
                  Text(
                    _fmt(_changeAmount),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: GcColors.onSecondary,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildDigitsGrid()),
        ],
      ),
    );
  }

  Widget _buildDigitsGrid() {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '⌫'],
    ];
    return Column(
      children: [
        for (final row in rows)
          Expanded(
            child: Row(
              children: [
                for (final key in row)
                  Expanded(child: _digitKey(key)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _digitKey(String key) {
    VoidCallback? onTap;
    Widget child;
    if (key == 'C') {
      onTap = _onClear;
      child = const Icon(Icons.refresh_rounded,
          color: GcColors.onSurface, size: 22);
    } else if (key == '⌫') {
      onTap = _onBackspace;
      child = const Icon(Icons.backspace_rounded,
          color: GcColors.onSurface, size: 22);
    } else {
      onTap = () => _onDigit(key);
      child = Text(
        key,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: GcColors.onSurface,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: GcColors.surfaceContainerLow,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: GcColors.outlineVariant),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  // --- Mixed tender strip ---------------------------------------------------

  Widget _buildTenderStrip() {
    if (!_calc.hasTenders) return const SizedBox.shrink();
    final live = _liveCalc;
    final paidCents = live.tenders.fold<int>(0, (s, t) => s + t.amountCents);
    final goal = live.grandTotalCents;
    final progress = goal <= 0 ? 0.0 : (paidCents / goal).clamp(0.0, 1.0);
    final progressPct = (progress * 100).round();
    final outstanding = live.outstandingCents;
    final fullyPaid = outstanding <= 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: GcColors.tertiary.withValues(alpha: 0.06),
        border: Border.all(color: GcColors.tertiary),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.space16,
          AppTokens.space12,
          AppTokens.space16,
          AppTokens.space12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row: status label + progress percentage.
            Row(
              children: [
                Icon(
                  fullyPaid
                      ? Icons.check_circle_rounded
                      : Icons.timelapse_rounded,
                  size: 16,
                  color: GcColors.tertiary,
                ),
                const SizedBox(width: AppTokens.space8),
                Expanded(
                  child: Text(
                    fullyPaid ? 'TÜMÜYLE ÖDENDİ' : 'TEILWEISE BEZAHLT',
                    style: const TextStyle(
                      fontFamily: 'WorkSans',
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      color: GcColors.tertiary,
                    ),
                  ),
                ),
                Text(
                  '$progressPct%',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: GcColors.tertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Progress bar.
            ClipRect(
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: GcColors.tertiary.withValues(alpha: 0.15),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(GcColors.tertiary),
              ),
            ),
            const SizedBox(height: AppTokens.space12),
            // Per-tender rows (vertical list, not Wrap — easier to scan
            // when there are >2 partials).
            for (int i = 0; i < _calc.tenders.length; i++) ...[
              _tenderRow(i, _calc.tenders[i]),
              if (i != _calc.tenders.length - 1)
                const SizedBox(height: AppTokens.space4),
            ],
            const SizedBox(height: AppTokens.space12),
            const Divider(color: GcColors.tertiary, height: 1),
            const SizedBox(height: AppTokens.space8),
            // KALAN — the visual anchor.
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    fullyPaid ? 'PARA ÜSTÜ' : 'KALAN',
                    style: const TextStyle(
                      fontFamily: 'WorkSans',
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      color: GcColors.onSurface,
                    ),
                  ),
                ),
                Text(
                  _fmt(outstanding.abs()),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color:
                        fullyPaid ? GcColors.secondary : GcColors.tertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One-line row for a staged tender — used in the v2 progress card.
  /// Replaces the older `Wrap`-laid chips so multi-partial bills read top-
  /// to-bottom like a receipt and the cashier can scan amounts vertically.
  Widget _tenderRow(int index, TenderEntry t) {
    final uiMethod = _uiMethodFor(t);
    final (icon, label) = switch (uiMethod) {
      _Method.bar => (Icons.payments_rounded, 'BAR'),
      _Method.karte => (Icons.credit_card_rounded, 'KARTE'),
      _Method.twint => (Icons.phone_iphone_rounded, 'TWINT'),
      _Method.gutschein => (Icons.confirmation_number_rounded, 'GUTSCHEIN'),
    };
    return Row(
      children: [
        Icon(
          Icons.check_circle_rounded,
          size: 14,
          color: GcColors.tertiary,
        ),
        const SizedBox(width: AppTokens.space8),
        Icon(icon, size: 16, color: GcColors.onSurface),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'WorkSans',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: GcColors.onSurface,
            ),
          ),
        ),
        Text(
          _fmt(t.amountCents),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: GcColors.onSurface,
          ),
        ),
        const SizedBox(width: AppTokens.space8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _removeTender(index),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: GcColors.tertiary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _stageTender() {
    if (!_canStage) return;
    final result = _liveCalc.addTender(
      method: _domainMethodFor(_method),
      amountCents: _enteredCents,
      reference: _referenceFor(_method),
    );
    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_stageErrorMessage(result.error!))),
      );
      return;
    }
    setState(() {
      _calc = result.calculator!;
      _amountStr = '';
      // Keep method as-is so rapid same-method partials are easy; the
      // cashier can tap another chip for the next tender if needed.
    });
  }

  void _removeTender(int index) {
    setState(() => _calc = _calc.removeTenderAt(index));
  }

  String _stageErrorMessage(AddTenderError e) {
    return switch (e) {
      AddTenderError.nonPositive => 'Geçerli bir tutar girin.',
      AddTenderError.overPayNonCash =>
        'Kart/TWINT/kuponla kalan tutardan fazlası alınamaz.',
      AddTenderError.alreadyFullyPaid => 'Adisyon zaten ödendi.',
    };
  }

  // --- Pay CTA -------------------------------------------------------------

  /// v2 CTA row: [+ EKLE]  [✓ ÖDE · CHF X]  [⊟ BÖL]
  ///  - EKLE only enabled when a partial tender is staged-able.
  ///  - BÖL surfaced here so the seat-split flow doesn't get buried in
  ///    the extras row anymore; cashiers report this is the action they
  ///    reach for *during* a payment, not before it.
  Widget _buildPayCta() {
    return SizedBox(
      height: AppTokens.touchLarge + 8,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _stageButton(),
          ),
          const SizedBox(width: AppTokens.space8),
          Expanded(
            flex: 7,
            child: _payButton(),
          ),
          const SizedBox(width: AppTokens.space8),
          Expanded(
            flex: 2,
            child: _splitButton(),
          ),
        ],
      ),
    );
  }

  Widget _splitButton() {
    return Material(
      color: GcColors.surfaceContainerLow,
      child: InkWell(
        onTap: _submitting
            ? null
            : () => context.push(AppRoutes.splitBillFor(widget.ticketId)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: GcColors.outline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.call_split_rounded,
                size: 20,
                color: _submitting
                    ? GcColors.outlineVariant
                    : GcColors.onSurface,
              ),
              const SizedBox(height: 2),
              Text(
                'BÖL',
                style: TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  color: _submitting
                      ? GcColors.outlineVariant
                      : GcColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stageButton() {
    final enabled = _canStage;
    return Material(
      color: enabled ? GcColors.tertiary : GcColors.surfaceContainerHighest,
      child: InkWell(
        onTap: enabled ? _stageTender : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled ? GcColors.tertiary : GcColors.outlineVariant,
            ),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 20,
                  color: enabled
                      ? GcColors.onPrimary
                      : GcColors.outlineVariant,
                ),
                const SizedBox(width: AppTokens.space4),
                Text(
                  'EKLE',
                  style: TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: enabled
                        ? GcColors.onPrimary
                        : GcColors.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _payButton() {
    final displayAmount = _calc.hasTenders ? _outstanding : _grandTotal;
    return Material(
      color: _canPay
          ? GcColors.primary
          : GcColors.surfaceContainerHighest,
      child: InkWell(
        onTap: _canPay ? _submit : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: _canPay ? kPrimaryGradient : null,
            border: Border(
              top: BorderSide(
                color: _canPay ? kInsetHighlight : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Center(
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 22,
                        color: _canPay
                            ? GcColors.onPrimary
                            : GcColors.outlineVariant,
                      ),
                      const SizedBox(width: AppTokens.space8),
                      Text(
                        'ÖDE · ${_fmt(displayAmount)}',
                        style: TextStyle(
                          fontFamily: 'WorkSans',
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: _canPay
                              ? GcColors.onPrimary
                              : GcColors.outlineVariant,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // --- Completion view -----------------------------------------------------

  Widget _buildCompletion() {
    return Scaffold(
      backgroundColor: GcColors.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: GcColors.secondaryDim,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 48,
                color: GcColors.onSecondary,
              ),
            ),
            const SizedBox(height: AppTokens.space24),
            const Text('Ödeme Tamamlandı', style: GcText.displayBlack),
            const SizedBox(height: AppTokens.space8),
            Text(
              'Rückgeld: ${_fmt(_changeAmount)}',
              style: GcText.headline.copyWith(color: GcColors.secondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Numeric dialog for choosing how many loyalty points to redeem.
///
/// Enforces a hard cap at [maxRedeemable] (= min(balance, bill room)) so
/// the operator can't accidentally debit more points than the bill or the
/// customer carries. Popping with a non-null int commits the selection;
/// popping with null cancels. 1 point redeems 1 cent.
class _LoyaltyRedeemDialog extends StatefulWidget {
  const _LoyaltyRedeemDialog({
    required this.balance,
    required this.maxRedeemable,
    required this.initial,
  });

  final int balance;
  final int maxRedeemable;
  final int initial;

  @override
  State<_LoyaltyRedeemDialog> createState() => _LoyaltyRedeemDialogState();
}

class _LoyaltyRedeemDialogState extends State<_LoyaltyRedeemDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial > 0 ? widget.initial.toString() : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _fmtCents(int cents) {
    final whole = (cents.abs() ~/ 100).toString();
    final frac = (cents.abs() % 100).toString().padLeft(2, '0');
    return 'CHF $whole.$frac';
  }

  void _commit() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      Navigator.of(context).pop(0);
      return;
    }
    final v = int.tryParse(raw);
    if (v == null || v < 0) {
      setState(() => _error = 'Geçerli bir sayı girin.');
      return;
    }
    if (v > widget.maxRedeemable) {
      setState(() =>
          _error = 'En fazla ${widget.maxRedeemable} puan kullanılabilir.');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: GcColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: GcColors.outlineVariant),
      ),
      title: const Text('Puan Kullan', style: GcText.headline),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mevcut bakiye: ${widget.balance} puan',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: GcColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Bu bilette en fazla ${widget.maxRedeemable} puan '
            '(${_fmtCents(widget.maxRedeemable)}) kullanılabilir.',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: GcColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.space12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              labelText: 'Kullanılacak puan',
              errorText: _error,
              border: const OutlineInputBorder(),
              suffixText: 'P',
            ),
            onSubmitted: (_) => _commit(),
          ),
          const SizedBox(height: AppTokens.space8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  _controller.text = widget.maxRedeemable.toString();
                  setState(() => _error = null);
                },
                child: const Text('TÜMÜNÜ KULLAN'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: _commit,
          style: FilledButton.styleFrom(
            backgroundColor: GcColors.tertiary,
            foregroundColor: GcColors.onPrimary,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
          ),
          child: const Text('Uygula'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _LiveStatusCard — shared layout for Cash Collector + MyPOS banners.
// ---------------------------------------------------------------------------

/// Centred status card used by the hardware-driven payment methods.
/// Visual anchor is the amount-due figure; the "go manual" affordance is
/// reduced to a single text link in the bottom row so it stops competing
/// with the primary ÖDE button. Pre-redesign these banners showed a large
/// OutlinedButton for the fallback which read as a co-equal action — the
/// operator hesitated which to tap.
class _LiveStatusCard extends StatelessWidget {
  const _LiveStatusCard({
    required this.icon,
    required this.headline,
    required this.statusLabel,
    required this.amountLabel,
    required this.amountFormatted,
    required this.hint,
    required this.manualLinkLabel,
    required this.onManual,
  });

  final IconData icon;
  final String headline;
  final String statusLabel;
  final String amountLabel;
  final String amountFormatted;
  final String hint;
  final String manualLinkLabel;
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: GcColors.surfaceContainerLowest,
        border: Border.all(color: GcColors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.space24,
          AppTokens.space16,
          AppTokens.space24,
          AppTokens.space12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top row — icon left, ready pill right.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 36, color: GcColors.primary),
                const Spacer(),
                _ReadyPill(label: statusLabel),
              ],
            ),
            const SizedBox(height: AppTokens.space12),
            Text(
              headline,
              style: const TextStyle(
                fontFamily: 'WorkSans',
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                color: GcColors.onSurface,
              ),
            ),
            const SizedBox(height: AppTokens.space24),
            // Amount block — the visual anchor.
            Text(
              amountLabel,
              style: const TextStyle(
                fontFamily: 'WorkSans',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: GcColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              amountFormatted,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 44,
                fontWeight: FontWeight.w900,
                color: GcColors.primary,
                height: 1.0,
              ),
            ),
            const Spacer(),
            // Helper line + small manual link.
            Text(
              hint,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: GcColors.onSurfaceVariant,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onManual,
                icon: const Icon(Icons.keyboard_rounded, size: 14),
                label: Text(manualLinkLabel),
                style: TextButton.styleFrom(
                  foregroundColor: GcColors.onSurfaceVariant,
                  textStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyPill extends StatelessWidget {
  const _ReadyPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: GcColors.secondaryDim,
        border: Border.all(color: GcColors.secondary),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: GcColors.secondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'WorkSans',
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: GcColors.onSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
