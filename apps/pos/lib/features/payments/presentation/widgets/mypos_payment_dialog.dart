/// MyPOS Sigma terminal — live card / TWINT payment dialog.
///
/// Opened from the payment screen (and the shell KART chip) when the
/// MyPOS toggle is on. The dialog connects to the terminal via the
/// existing [MyPosClient] (MethodChannel-backed Kotlin plugin), kicks
/// off the requested payment, and pops once the terminal returns an
/// approved transaction (or the operator cancels / falls back).
///
/// Pattern intentionally mirrors `cash_collector_dialog.dart` so the
/// operator sees the same shape (live state, Cancel, Manuel girişe geç)
/// for all three terminal-driven payment methods.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/mypos/mypos_client.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/payment_settings.dart';

/// What we ask MyPOS to do this round.
enum MyPosFlow { card, twint }

class MyPosPaymentResult {
  const MyPosPaymentResult({
    required this.approved,
    required this.amountCents,
    required this.flow,
    this.transactionId = '',
    this.authCode,
    this.cardType,
    this.maskedPan,
    this.errorMessage,
    this.fallbackToManual = false,
  });

  /// True only when the terminal returned an approval (status=APPROVED +
  /// non-empty transaction proof). False on decline, network error, or
  /// fallback.
  final bool approved;

  /// Amount actually charged (rappen). Equals the requested amount on
  /// success; zero on decline / fallback.
  final int amountCents;

  final MyPosFlow flow;
  final String transactionId;
  final String? authCode;
  final String? cardType;
  final String? maskedPan;
  final String? errorMessage;

  /// Sentinel "operator chose to record the payment manually" — caller
  /// should fall through to the legacy in-POS path (no terminal call).
  final bool fallbackToManual;

  static const MyPosPaymentResult manualFallback = MyPosPaymentResult(
    approved: false,
    amountCents: 0,
    flow: MyPosFlow.card,
    fallbackToManual: true,
  );
}

Future<MyPosPaymentResult?> showMyPosPaymentDialog(
  BuildContext context, {
  required MyPosConfig config,
  required int amountCents,
  required MyPosFlow flow,
}) {
  return showDialog<MyPosPaymentResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _MyPosPaymentDialog(
      config: config,
      amountCents: amountCents,
      flow: flow,
    ),
  );
}

enum _DialogState {
  connecting,
  awaitingCard,
  processing,
  approved,
  declined,
  failed,
}

class _MyPosPaymentDialog extends StatefulWidget {
  const _MyPosPaymentDialog({
    required this.config,
    required this.amountCents,
    required this.flow,
  });

  final MyPosConfig config;
  final int amountCents;
  final MyPosFlow flow;

  @override
  State<_MyPosPaymentDialog> createState() => _MyPosPaymentDialogState();
}

class _MyPosPaymentDialogState extends State<_MyPosPaymentDialog> {
  MyPosClient? _client;
  _DialogState _state = _DialogState.connecting;
  String _statusText = 'Terminal’e bağlanılıyor…';
  String? _errorMessage;
  String? _transactionId;
  String? _authCode;
  String? _cardType;
  String? _maskedPan;

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _disposed = true;
    // Intentionally NO disconnect() here. The terminal session is shared
    // across the app: bootstrap connects once at app startup and we keep
    // it warm so the next sale doesn't pay the 1-3 s SDK handshake again.
    // Pre-v3 this dispose called disconnect() and every dialog close
    // tore down the session — which then raced the next payment into a
    // "Terminal not connected (state: CONNECTING)" decline.
    super.dispose();
  }

  Future<void> _run() async {
    final client = MyPosClient(
      terminalIp: widget.config.ip,
      terminalPort: widget.config.port,
      onConnectionStateChanged: (connected, state, reason) {
        if (_disposed || !mounted) return;
        if (connected && _state == _DialogState.connecting) {
          setState(() {
            _state = _DialogState.awaitingCard;
            _statusText = widget.flow == MyPosFlow.twint
                ? 'Müşteri TWINT QR’ı okutsun.'
                : 'Müşteri kartı yaklaştırsın / taksın.';
          });
        }
      },
    );
    _client = client;

    // Native plugin's `handleConfigure` always flips state to CONNECTING
    // (line 137 of MyPosPlugin.kt) and the SDK fires onConnected ~1-3s
    // later. If we call connect() again here when the terminal is already
    // connected from app startup, we *demote* it back to CONNECTING and
    // race the SDK on the way back up — which is exactly how the
    // "Terminal not connected (state: CONNECTING)" decline reproduces.
    //
    // Probe the plugin first; only configure if it's actually offline.
    final alreadyConnected = await client.checkConnection();
    if (!mounted || _disposed) return;

    if (!alreadyConnected) {
      final configured = await client.connect();
      if (!mounted || _disposed) return;
      if (!configured) {
        _fail('Terminale bağlanılamadı. IP/Port’u kontrol et veya manuel’e geç.');
        return;
      }
      // Poll for actual SDK-level connection (configure success ≠ TCP up).
      // 4 s window is enough for the Sigma; if longer, the SDK is broken.
      final deadline =
          DateTime.now().add(const Duration(seconds: 4));
      var ready = false;
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (_disposed) return;
        if (await client.checkConnection()) {
          ready = true;
          break;
        }
      }
      if (!mounted || _disposed) return;
      if (!ready) {
        _fail('Terminal bağlantısı doğrulanamadı (4 s). Cihazı kontrol et.');
        return;
      }
    }

    setState(() {
      _state = _DialogState.awaitingCard;
      _statusText = widget.flow == MyPosFlow.twint
          ? 'Müşteri TWINT QR’ı okutsun.'
          : 'Müşteri kartı yaklaştırsın / taksın.';
    });

    try {
      final MyPosPaymentResult result;
      if (widget.flow == MyPosFlow.twint) {
        final r = await client.processTwintPayment(amountCents: widget.amountCents);
        result = _resultFromClient(r, MyPosFlow.twint);
      } else {
        final r = await client.processPayment(
          amountCents: widget.amountCents,
          currency: widget.config.currency,
        );
        result = _resultFromClient(r, MyPosFlow.card);
      }

      if (!mounted || _disposed) return;
      if (result.approved) {
        setState(() {
          _state = _DialogState.approved;
          _statusText = 'Onaylandı';
          _transactionId = result.transactionId;
          _authCode = result.authCode;
          _cardType = result.cardType;
          _maskedPan = result.maskedPan;
        });
        // Give the operator ~600 ms to register the success before closing.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted || _disposed) return;
        Navigator.of(context).pop(result);
      } else {
        setState(() {
          _state = _DialogState.declined;
          _statusText = result.errorMessage ?? 'Reddedildi';
          _errorMessage = result.errorMessage;
        });
      }
    } catch (e) {
      if (!mounted || _disposed) return;
      _fail('Terminal hatası: $e');
    }
  }

  void _fail(String message) {
    setState(() {
      _state = _DialogState.failed;
      _statusText = message;
      _errorMessage = message;
    });
  }

  MyPosPaymentResult _resultFromClient(
    dynamic /* MyPosPaymentResult from client */ r,
    MyPosFlow flow,
  ) {
    final success = r.success as bool;
    final txId = (r.transactionId as String?) ?? '';
    return MyPosPaymentResult(
      approved: success && txId.isNotEmpty,
      amountCents: success ? widget.amountCents : 0,
      flow: flow,
      transactionId: txId,
      authCode: r.authCode as String?,
      cardType: r.cardType as String?,
      maskedPan: r.maskedPan as String?,
      errorMessage: r.errorMessage as String?,
    );
  }

  Future<void> _cancel() async {
    if (_state == _DialogState.approved) return;
    try {
      await _client?.cancelTransaction();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _fallback() {
    Navigator.of(context).pop(MyPosPaymentResult.manualFallback);
  }

  String _fmt(int cents) {
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    final cur = widget.flow == MyPosFlow.twint ? 'CHF' : widget.config.currency;
    return '$cur $whole.$frac';
  }

  IconData get _flowIcon =>
      widget.flow == MyPosFlow.twint
          ? Icons.qr_code_2_rounded
          : Icons.credit_card_rounded;

  String get _flowLabel =>
      widget.flow == MyPosFlow.twint ? 'TWINT TERMİNALİ' : 'KART TERMİNALİ';

  Color get _stateAccent => switch (_state) {
        _DialogState.approved => GcColors.secondary,
        _DialogState.declined || _DialogState.failed => GcColors.error,
        _ => GcColors.primary,
      };

  bool get _canFallback =>
      _state == _DialogState.failed ||
      _state == _DialogState.declined ||
      _state == _DialogState.connecting;

  @override
  Widget build(BuildContext context) {
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
                  Icon(_flowIcon, color: _stateAccent, size: 26),
                  const SizedBox(width: AppTokens.space8),
                  Expanded(
                    child: Text(
                      _flowLabel,
                      style: const TextStyle(
                        fontFamily: 'WorkSans',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        color: GcColors.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    _stateBadge(),
                    style: TextStyle(
                      fontFamily: 'WorkSans',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: _stateAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.space16),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tutar',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: GcColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    _fmt(widget.amountCents),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: GcColors.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.space8),
              ClipRRect(
                borderRadius: BorderRadius.zero,
                child: LinearProgressIndicator(
                  value: _state == _DialogState.approved ? 1.0 : null,
                  minHeight: 10,
                  backgroundColor: GcColors.surfaceContainerLow,
                  color: _stateAccent,
                ),
              ),
              const SizedBox(height: AppTokens.space16),
              Text(
                _statusText,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: GcColors.onSurface,
                ),
              ),
              if (_state == _DialogState.approved) ...[
                const SizedBox(height: AppTokens.space12),
                if ((_cardType ?? '').isNotEmpty)
                  _kv('Kart', _cardType!),
                if ((_maskedPan ?? '').isNotEmpty)
                  _kv('Pan', _maskedPan!),
                if ((_authCode ?? '').isNotEmpty)
                  _kv('Auth', _authCode!),
                if ((_transactionId ?? '').isNotEmpty)
                  _kv('Tx', _transactionId!),
              ],
              if ((_state == _DialogState.failed ||
                      _state == _DialogState.declined) &&
                  (_errorMessage ?? '').isNotEmpty) ...[
                const SizedBox(height: AppTokens.space12),
                Container(
                  padding: const EdgeInsets.all(AppTokens.space8),
                  decoration: BoxDecoration(
                    color: GcColors.error.withValues(alpha: 0.08),
                    border: Border.all(color: GcColors.error),
                  ),
                  child: Text(
                    _errorMessage!,
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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _state == _DialogState.approved ? null : _cancel,
                      style: OutlinedButton.styleFrom(
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        minimumSize:
                            const Size.fromHeight(AppTokens.touchLarge),
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
                  if (_canFallback) ...[
                    const SizedBox(width: AppTokens.space8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _fallback,
                        style: FilledButton.styleFrom(
                          backgroundColor: GcColors.tertiary,
                          foregroundColor: GcColors.onPrimary,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                          minimumSize:
                              const Size.fromHeight(AppTokens.touchLarge),
                        ),
                        icon: const Icon(Icons.keyboard_rounded, size: 18),
                        label: const Text(
                          'MANUEL’E GEÇ',
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                k,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  color: GcColors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                v,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: GcColors.onSurface,
                ),
              ),
            ),
          ],
        ),
      );

  String _stateBadge() => switch (_state) {
        _DialogState.connecting => 'BAĞLANIYOR',
        _DialogState.awaitingCard => 'BEKLENİYOR',
        _DialogState.processing => 'İŞLENİYOR',
        _DialogState.approved => 'ONAYLANDI',
        _DialogState.declined => 'REDDEDİLDİ',
        _DialogState.failed => 'HATA',
      };
}
