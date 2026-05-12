/// Cash Collector (EcoCash V4.2) — live sale dialog.
///
/// Shown when the operator taps ÖDE on a BAR (cash) tender while the Cash
/// Collector is enabled in Settings. Spins up a [CashCollectorSaleEngine],
/// streams progress (collected/dispensed amounts), and pops with one of:
///
///   * a non-null [CashCollectorResult] on success — caller persists the
///     payment using `collected` as the tendered amount,
///   * null if the operator cancels before the device accepts any cash.
///
/// Errors from the kiosk (insufficient float, jam, network) are surfaced
/// inline with a "Geri" affordance so the operator can fall back to manual
/// cash entry without losing the ticket state.
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/ecocash/cash_collector_sale_engine.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/ecocash/ecocash_client.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/ecocash/ecocash_models.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/payment_settings.dart';

class CashCollectorResult {
  const CashCollectorResult({
    required this.collected,
    required this.dispensed,
    required this.refund,
    required this.transId,
    required this.orderId,
    this.fallbackToManual = false,
  });

  /// Amount inserted by the customer (rappen). Equals or exceeds the bill.
  final int collected;

  /// Change auto-dispensed by the device (rappen).
  final int dispensed;

  /// Cash the device could NOT dispense and the operator must hand back
  /// manually (rappen). Zero on the happy path.
  final int refund;

  final String transId;
  final String orderId;

  /// True when the operator decided to bail out of the device flow and
  /// enter cash manually instead — e.g. kiosk offline, jam they can't
  /// clear, or just preference. Caller should open the manual cash
  /// dialog (or unhide the numpad) when this is set.
  final bool fallbackToManual;

  /// Sentinel result used to indicate "abort device flow, switch to
  /// manual cash for this transaction".
  static const CashCollectorResult manualFallback = CashCollectorResult(
    collected: 0,
    dispensed: 0,
    refund: 0,
    transId: '',
    orderId: '',
    fallbackToManual: true,
  );
}

/// Opens the dialog. Returns the result, or null if cancelled / no cash
/// was inserted before the operator aborted.
Future<CashCollectorResult?> showCashCollectorDialog(
  BuildContext context, {
  required CashCollectorConfig config,
  required int saleAmountCents,
}) {
  return showDialog<CashCollectorResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CashCollectorDialog(
      config: config,
      saleAmountCents: saleAmountCents,
    ),
  );
}

class _CashCollectorDialog extends StatefulWidget {
  const _CashCollectorDialog({
    required this.config,
    required this.saleAmountCents,
  });

  final CashCollectorConfig config;
  final int saleAmountCents;

  @override
  State<_CashCollectorDialog> createState() => _CashCollectorDialogState();
}

class _CashCollectorDialogState extends State<_CashCollectorDialog> {
  late final EcoCashClient _client;
  late final CashCollectorSaleEngine _engine;
  CashCollectorTransaction? _txn;

  @override
  void initState() {
    super.initState();
    _client = EcoCashClient(EcoCashConfig(
      baseUrl: widget.config.baseUrl,
      deviceId: widget.config.deviceId,
      clientId: widget.config.clientId,
      tokenPass: widget.config.tokenPass,
      currency: widget.config.currency,
    ));
    _engine = CashCollectorSaleEngine(_client);
    _engine.transaction.listen((t) {
      if (!mounted) return;
      setState(() => _txn = t);
      if (t != null && t.state == CashCollectorState.completed) {
        Navigator.of(context).pop(CashCollectorResult(
          collected: t.collected,
          dispensed: t.dispensed,
          refund: t.refund,
          transId: t.transId ?? '',
          orderId: t.orderId,
        ));
      }
    });
    _engine.start(
      saleAmount: widget.saleAmountCents,
      currency: widget.config.currency,
    );
  }

  @override
  void dispose() {
    _engine.dispose();
    _client.close();
    super.dispose();
  }

  Future<void> _cancel() async {
    final t = _txn;
    // If money has already been inserted, do NOT just close — make the
    // operator explicitly confirm so we don't accidentally leave cash
    // trapped in escrow.
    if (t != null && t.collected > 0 && t.state != CashCollectorState.failed) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Satış iptal edilsin mi?'),
          content: Text(
            'Müşteri ${_fmt(t.collected)} para verdi. '
            'İptal edersek cihaz parayı iade edecek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hayır, devam et'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Evet, iptal et'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _engine.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String _fmt(int cents) {
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return '${widget.config.currency} $whole.$frac';
  }

  @override
  Widget build(BuildContext context) {
    final t = _txn;
    final sale = widget.saleAmountCents;
    final collected = t?.collected ?? 0;
    final dispensed = t?.dispensed ?? 0;
    final state = t?.state ?? CashCollectorState.starting;
    final remaining = collected < sale ? sale - collected : 0;
    final progress = sale > 0
        ? (collected / sale).clamp(0.0, 1.0)
        : 0.0;

    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: GcColors.outlineVariant),
      ),
      backgroundColor: GcColors.surfaceContainerLowest,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.savings_rounded,
                      color: GcColors.primary, size: 26),
                  const SizedBox(width: AppTokens.space8),
                  const Expanded(
                    child: Text(
                      'KASA OTOMATI',
                      style: TextStyle(
                        fontFamily: 'WorkSans',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        color: GcColors.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    _stateLabel(state),
                    style: const TextStyle(
                      fontFamily: 'WorkSans',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: GcColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.space16),
              _amountRow('Tutar', _fmt(sale), big: true),
              const SizedBox(height: AppTokens.space8),
              ClipRRect(
                borderRadius: BorderRadius.zero,
                child: LinearProgressIndicator(
                  value: state == CashCollectorState.starting
                      ? null
                      : progress,
                  minHeight: 10,
                  backgroundColor: GcColors.surfaceContainerLow,
                  color: GcColors.primary,
                ),
              ),
              const SizedBox(height: AppTokens.space16),
              _amountRow('Alınan', _fmt(collected)),
              _amountRow('Kalan', _fmt(remaining)),
              if (dispensed > 0)
                _amountRow('Para üstü', _fmt(dispensed),
                    color: GcColors.secondary),
              if (t?.refund != null && t!.refund > 0)
                _amountRow(
                  'Elden iade gerekli',
                  _fmt(t.refund),
                  color: GcColors.error,
                ),
              const SizedBox(height: AppTokens.space12),
              Text(
                _hint(state),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: GcColors.onSurfaceVariant,
                ),
              ),
              if (state == CashCollectorState.failed &&
                  (t?.errorMessage ?? '').isNotEmpty) ...[
                const SizedBox(height: AppTokens.space8),
                Container(
                  padding: const EdgeInsets.all(AppTokens.space8),
                  decoration: BoxDecoration(
                    color: GcColors.error.withValues(alpha: 0.08),
                    border: Border.all(color: GcColors.error),
                  ),
                  child: Text(
                    t!.errorMessage!,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: GcColors.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppTokens.space16),
              _buildActions(state, collected),
            ],
          ),
        ),
      ),
    );
  }

  /// Action row. When the device flow is healthy → single "İptal".
  /// When it has failed (or hasn't accepted any cash yet) → also offer
  /// "Manuel girişe geç" so the cashier can recover without losing the
  /// ticket. Once cash is in escrow we hide the manual switch — that
  /// path would orphan the inserted money.
  Widget _buildActions(CashCollectorState state, int collected) {
    final canFallback =
        collected == 0 && state != CashCollectorState.completed;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed:
                state == CashCollectorState.completed ? null : _cancel,
            style: OutlinedButton.styleFrom(
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              minimumSize: const Size.fromHeight(AppTokens.touchLarge),
            ),
            child: const Text(
              'İptal',
              style: TextStyle(
                fontFamily: 'WorkSans',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
        if (canFallback) ...[
          const SizedBox(width: AppTokens.space8),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context)
                  .pop(CashCollectorResult.manualFallback),
              style: FilledButton.styleFrom(
                backgroundColor: GcColors.tertiary,
                foregroundColor: GcColors.onPrimary,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                minimumSize: const Size.fromHeight(AppTokens.touchLarge),
              ),
              icon: const Icon(Icons.keyboard_rounded, size: 18),
              label: const Text(
                'MANUEL GİRİŞE GEÇ',
                style: TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _amountRow(String label, String value,
      {Color? color, bool big = false}) {
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
              fontSize: big ? 22 : 14,
              fontWeight: big ? FontWeight.w900 : FontWeight.w800,
              color: color ?? GcColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _stateLabel(CashCollectorState s) => switch (s) {
        CashCollectorState.starting => 'BAŞLATILIYOR',
        CashCollectorState.awaitingCash => 'PARA BEKLENİYOR',
        CashCollectorState.partial => 'KISMİ ALINDI',
        CashCollectorState.paidEnough => 'YETERLİ',
        CashCollectorState.dispensingChange => 'PARA ÜSTÜ VERİLİYOR',
        CashCollectorState.completed => 'TAMAMLANDI',
        CashCollectorState.failed => 'HATA',
        CashCollectorState.cancelled => 'İPTAL',
        CashCollectorState.idle => 'HAZIR',
      };

  String _hint(CashCollectorState s) => switch (s) {
        CashCollectorState.starting =>
          'Cihaza bağlanılıyor. Lütfen bekleyin.',
        CashCollectorState.awaitingCash =>
          'Müşteri parayı kasa otomatına yerleştirebilir.',
        CashCollectorState.partial =>
          'Kalan tutar için para bekleniyor.',
        CashCollectorState.paidEnough =>
          'Tutar tamam. Para üstü hesaplanıyor.',
        CashCollectorState.dispensingChange =>
          'Cihaz para üstünü veriyor.',
        CashCollectorState.completed => 'Ödeme tamamlandı.',
        CashCollectorState.failed =>
          'Cihaz hatası. Manuel nakit girişine geçilebilir.',
        CashCollectorState.cancelled =>
          'Satış iptal edildi. Cihaz parayı iade ediyor.',
        CashCollectorState.idle => '',
      };
}
