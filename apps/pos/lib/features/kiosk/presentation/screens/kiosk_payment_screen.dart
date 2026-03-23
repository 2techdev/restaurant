/// Kiosk payment selection screen.
///
/// Offers two payment methods:
///   1. "Pay at Counter" — shows an order number and asks the customer
///      to pay at the POS. The order is submitted immediately so the
///      kitchen can start as soon as the customer walks over.
///   2. "Pay with Card" — triggers the integrated card terminal
///      (Wallee / MyPOS). The order is submitted after successful
///      terminal authorisation.
///
/// Both paths navigate to [KioskConfirmationScreen] on success.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/utils/money.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/providers/kiosk_provider.dart';
import 'package:gastrocore_pos/features/kiosk/router/kiosk_router.dart';
import 'package:gastrocore_pos/features/kiosk/services/kiosk_order_service.dart';
import 'package:gastrocore_pos/features/kiosk/theme/kiosk_theme.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_welcome_screen.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_language_screen.dart';
import 'package:gastrocore_pos/core/di/providers.dart';

class KioskPaymentScreen extends ConsumerStatefulWidget {
  const KioskPaymentScreen({super.key});

  @override
  ConsumerState<KioskPaymentScreen> createState() => _KioskPaymentScreenState();
}

class _KioskPaymentScreenState extends ConsumerState<KioskPaymentScreen> {
  bool _isProcessing = false;
  String? _error;

  Future<void> _submitAndNavigate({required bool payAtCounter}) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final session = ref.read(kioskSessionProvider);
      final tenantId = ref.read(tenantIdProvider);
      final deviceId = ref.read(deviceIdProvider);
      final svc = ref.read(kioskOrderServiceProvider);

      final orderNumber = await svc.submitOrder(
        tenantId: tenantId,
        deviceId: deviceId,
        items: session.items,
        orderType: session.orderType,
      );

      ref.read(kioskSessionProvider.notifier).setConfirmedOrder(orderNumber);

      if (mounted) {
        context.go(KioskRoutes.confirmation);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _onPayAtCounter() => _submitAndNavigate(payAtCounter: true);

  Future<void> _onPayWithCard() async {
    // Card payment: in a real integration we would call the Wallee / MyPOS
    // terminal SDK here and await authorisation before submitting the order.
    // For this skeleton we show a simulated "processing" state then submit.
    await _submitAndNavigate(payAtCounter: false);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(kioskSessionProvider);
    final total = KioskOrderService.roundToFiveRappen(session.subtotal);

    return Scaffold(
      backgroundColor: KioskColors.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            _PaymentHeader(
              onBack: _isProcessing ? null : () => context.go(KioskRoutes.cart),
            ),

            // ── Body ───────────────────────────────────────────────────────
            Expanded(
              child: _isProcessing
                  ? const _ProcessingView()
                  : _PaymentOptions(
                      total: total,
                      error: _error,
                      onPayAtCounter: _onPayAtCounter,
                      onPayWithCard: _onPayWithCard,
                    ),
            ),

            // ── Step indicator ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: const KioskStepIndicator(currentStep: 3),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _PaymentHeader extends StatelessWidget {
  final VoidCallback? onBack;
  const _PaymentHeader({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: KioskColors.bgCard,
        border: Border(bottom: BorderSide(color: KioskColors.border)),
      ),
      child: Row(
        children: [
          if (onBack != null) KioskBackButton(onTap: onBack!),
          const SizedBox(width: 20),
          Text(
            'Payment',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment options
// ---------------------------------------------------------------------------

class _PaymentOptions extends StatelessWidget {
  final int total;
  final String? error;
  final VoidCallback onPayAtCounter;
  final VoidCallback onPayWithCard;

  const _PaymentOptions({
    required this.total,
    required this.error,
    required this.onPayAtCounter,
    required this.onPayWithCard,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          // Total display
          Text(
            'Total to pay',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: KioskColors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            Money(total).format('CHF'),
            style: const TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w900,
              color: KioskColors.primary,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'incl. Swiss VAT (MwSt)',
            style: TextStyle(
              fontSize: 14,
              color: KioskColors.textDim,
            ),
          ),

          const SizedBox(height: 56),

          // Error message
          if (error != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: KioskColors.errorContainer,
                borderRadius: BorderRadius.circular(kKioskRadiusMedium),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: KioskColors.error, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Payment failed. Please try again.',
                      style: const TextStyle(color: KioskColors.error),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],

          // Payment method cards
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Row(
              children: [
                Expanded(
                  child: _PaymentMethodCard(
                    icon: Icons.point_of_sale_rounded,
                    title: 'Pay at Counter',
                    subtitle:
                        'Pick up your order number and\npay at the cashier',
                    color: KioskColors.secondary,
                    onTap: onPayAtCounter,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _PaymentMethodCard(
                    icon: Icons.credit_card_rounded,
                    title: 'Pay with Card',
                    subtitle:
                        'Tap or insert your card\non the terminal below',
                    color: KioskColors.primary,
                    onTap: onPayWithCard,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment method card
// ---------------------------------------------------------------------------

class _PaymentMethodCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _PaymentMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  State<_PaymentMethodCard> createState() => _PaymentMethodCardState();
}

class _PaymentMethodCardState extends State<_PaymentMethodCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    await _ctrl.forward();
    await _ctrl.reverse();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTap: _onTap,
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(kKioskRadiusXL),
            border: Border.all(color: widget.color.withValues(alpha: 0.4), width: 2),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  size: 40,
                  color: widget.color,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.color,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: KioskColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Processing view
// ---------------------------------------------------------------------------

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            strokeWidth: 6,
            color: KioskColors.primary,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Processing payment…',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          'Please do not close this screen',
          style: TextStyle(
            fontSize: 16,
            color: KioskColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
