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
import 'package:gastrocore_pos/features/payments/presentation/providers/refund_provider.dart';
import 'package:gastrocore_pos/features/payments/presentation/widgets/voucher_dialog.dart';

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
    if (_enteredCents <= _grandTotal) return 0;
    return _enteredCents - _grandTotal;
  }

  bool get _canPay {
    if (_submitting || _grandTotal <= 0) return false;
    if (_method == _Method.bar) return _enteredCents >= _grandTotal;
    return true; // Non-cash methods assume exact-total tender.
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
    setState(() => _submitting = true);

    final tenantId = ref.read(tenantIdProvider);
    final currentUser = ref.read(currentUserProvider);
    final receivedBy = currentUser?.name ?? 'POS';

    final domainMethod = switch (_method) {
      _Method.bar => PaymentMethod.cash,
      _Method.karte => PaymentMethod.creditCard,
      _Method.twint => PaymentMethod.other,
      _Method.gutschein => PaymentMethod.other,
    };

    final tendered =
        _method == _Method.bar ? _enteredCents : _grandTotal;

    final reference = switch (_method) {
      _Method.twint => 'TWINT',
      _Method.gutschein =>
        _voucher != null ? 'VOUCHER:${_voucher!.code}' : 'GUTSCHEIN',
      _ when _voucher != null => 'VOUCHER:${_voucher!.code}',
      _ => null,
    };

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
      await paymentRepo.processPayment(
        ticketId: widget.ticketId,
        tenantId: tenantId,
        paymentMethod: domainMethod,
        amount: _grandTotal,
        tipAmount: _tipAmount,
        tenderedAmount: tendered,
        receivedBy: receivedBy,
        reference: reference,
      );

      ref.read(currentTicketProvider.notifier).clear();
      if (!mounted) return;
      setState(() => _paymentComplete = true);
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
          onTap: () => setState(() => _method = m),
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
    return Container(
      padding: const EdgeInsets.all(AppTokens.space8),
      decoration: BoxDecoration(
        color: GcColors.surfaceContainerLowest,
        border: Border.all(color: GcColors.outlineVariant),
      ),
      child: Row(
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
          _tipChip('5%', _selectedTipPercent == 5, () => _applyTipPercent(5)),
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

  Widget _extraRow() {
    return Row(
      children: [
        Expanded(
          child: _extraButton(
            icon: Icons.card_giftcard_rounded,
            label: _voucher == null
                ? 'GUTSCHEIN'
                : 'GUTSCHEIN · ${_voucher!.code}',
            onTap: _voucher == null ? _pickVoucher : _clearVoucher,
            active: _voucher != null,
          ),
        ),
        const SizedBox(width: AppTokens.space8),
        Expanded(
          child: _extraButton(
            icon: Icons.call_split_rounded,
            label: 'BÖL',
            onTap: () => context.push(AppRoutes.splitBillFor(widget.ticketId)),
          ),
        ),
      ],
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
    if (_method == _Method.bar) return _buildNumpad();
    return _buildTerminalHint();
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

  // --- Terminal hint (card / twint / gutschein) -----------------------------

  Widget _buildTerminalHint() {
    final label = switch (_method) {
      _Method.karte => 'Kartenterminal',
      _Method.twint => 'TWINT QR / Tel.',
      _Method.gutschein => 'Gutschein',
      _Method.bar => '',
    };
    final detail = switch (_method) {
      _Method.karte =>
        'Tutarı müşterinin kartıyla terminalden işleyin ve onay aldıktan sonra ÖDE tuşuna basın.',
      _Method.twint =>
        'TWINT QR\'ını müşteriye gösterin, ödeme onayı alındıktan sonra ÖDE tuşuna basın.',
      _Method.gutschein =>
        'Gutschein kullanıyorsanız GUTSCHEIN alanından kodu girin, sonra ÖDE tuşuna basın.',
      _Method.bar => '',
    };

    return Container(
      padding: const EdgeInsets.all(AppTokens.space24),
      decoration: BoxDecoration(
        color: GcColors.surfaceContainerLowest,
        border: Border.all(color: GcColors.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            switch (_method) {
              _Method.karte => Icons.credit_card_rounded,
              _Method.twint => Icons.phone_iphone_rounded,
              _Method.gutschein => Icons.confirmation_number_rounded,
              _Method.bar => Icons.payments_rounded,
            },
            size: 56,
            color: GcColors.onSurfaceVariant,
          ),
          const SizedBox(height: AppTokens.space16),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: GcText.headline,
          ),
          const SizedBox(height: AppTokens.space8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: GcText.body,
          ),
        ],
      ),
    );
  }

  // --- Pay CTA -------------------------------------------------------------

  Widget _buildPayCta() {
    return SizedBox(
      height: AppTokens.touchLarge + 8,
      child: Material(
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
                          'ÖDE · ${_fmt(_grandTotal)}',
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
