/// Order tracking screen — real-time status via polling.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gastrocore_online/core/theme/app_theme.dart';
import 'package:gastrocore_online/domain/models/order_models.dart';
import 'package:gastrocore_online/l10n/app_localizations.dart';
import 'package:gastrocore_online/providers/order_provider.dart';

class OrderTrackingScreen extends ConsumerWidget {
  const OrderTrackingScreen({
    super.key,
    required this.restaurantId,
    required this.orderId,
  });

  final String restaurantId;
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final trackingAsync = ref.watch(orderTrackingProvider(orderId));

    return Scaffold(
      backgroundColor: OnlineColors.bgPage,
      appBar: AppBar(
        backgroundColor: OnlineColors.charcoal,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.go('/$restaurantId/menu'),
        ),
        title: Text(
          l10n.orderStatus,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        centerTitle: false,
      ),
      body: trackingAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: OnlineColors.primary),
        ),
        error: (_, __) => _buildView(context, l10n, null),
        data: (status) => _buildView(context, l10n, status),
      ),
    );
  }

  Widget _buildView(
    BuildContext context,
    AppLocalizations l10n,
    OrderStatusResponse? status,
  ) {
    final currentStatus = status?.status ?? OrderStatus.received;
    final currentIdx = _statusIndex(currentStatus);

    final steps = [
      _Step(status: OrderStatus.received, label: l10n.statusReceived, icon: Icons.receipt_long_rounded),
      _Step(status: OrderStatus.preparing, label: l10n.statusPreparing, icon: Icons.local_fire_department_rounded),
      _Step(status: OrderStatus.ready, label: l10n.statusReady, icon: Icons.check_circle_outline_rounded),
      _Step(status: OrderStatus.served, label: l10n.statusServed, icon: Icons.restaurant_rounded),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Order card
          if (status != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: OnlineColors.bgCard,
                borderRadius: BorderRadius.circular(kRadiusXl),
                border: Border.all(color: OnlineColors.divider),
              ),
              child: Column(
                children: [
                  Text(
                    l10n.orderNumber('${status.orderNumber}'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: OnlineColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.access_time_rounded,
                          size: 15, color: OnlineColors.textSecondary),
                      const SizedBox(width: 5),
                      Text(
                        l10n.estimatedWait('${status.estimatedWaitMinutes}'),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: OnlineColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],

          // Timeline
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: OnlineColors.bgCard,
              borderRadius: BorderRadius.circular(kRadiusXl),
              border: Border.all(color: OnlineColors.divider),
            ),
            child: Column(
              children: [
                for (int i = 0; i < steps.length; i++)
                  _StepWidget(
                    step: steps[i],
                    state: _getState(i, currentIdx),
                    isLast: i == steps.length - 1,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Back to menu
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/$restaurantId/menu'),
              icon: const Icon(Icons.restaurant_menu_rounded),
              label: Text(l10n.backToMenu),
            ),
          ),
          const SizedBox(height: 20),

          // Polling indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: OnlineColors.textDim,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Wird alle 10 Sekunden aktualisiert',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: OnlineColors.textDim,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _statusIndex(OrderStatus status) {
    switch (status) {
      case OrderStatus.received:
        return 0;
      case OrderStatus.preparing:
        return 1;
      case OrderStatus.ready:
        return 2;
      case OrderStatus.served:
        return 3;
      default:
        return 0;
    }
  }

  _StepState _getState(int idx, int currentIdx) {
    if (idx < currentIdx) return _StepState.done;
    if (idx == currentIdx) return _StepState.active;
    return _StepState.pending;
  }
}

// ---------------------------------------------------------------------------
// Step model
// ---------------------------------------------------------------------------

enum _StepState { done, active, pending }

class _Step {
  const _Step({
    required this.status,
    required this.label,
    required this.icon,
  });
  final OrderStatus status;
  final String label;
  final IconData icon;
}

// ---------------------------------------------------------------------------
// Step widget
// ---------------------------------------------------------------------------

class _StepWidget extends StatelessWidget {
  const _StepWidget({
    required this.step,
    required this.state,
    required this.isLast,
  });

  final _Step step;
  final _StepState state;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final Color iconBg;
    final Color iconColor;
    final Color lineColor;

    switch (state) {
      case _StepState.done:
        iconBg = OnlineColors.green;
        iconColor = Colors.white;
        lineColor = OnlineColors.green;
      case _StepState.active:
        iconBg = OnlineColors.primary;
        iconColor = Colors.white;
        lineColor = OnlineColors.divider;
      case _StepState.pending:
        iconBg = OnlineColors.pillInactiveBg;
        iconColor = OnlineColors.textDim;
        lineColor = OnlineColors.divider;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon column
        Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: state == _StepState.active
                  ? _PulseIcon(icon: step.icon, color: iconColor)
                  : (state == _StepState.done
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 22,
                        )
                      : Icon(step.icon, color: iconColor, size: 20)),
            ),
            if (!isLast)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 2,
                height: 36,
                color: lineColor,
              ),
          ],
        ),
        const SizedBox(width: 16),

        // Label
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: state == _StepState.active
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: state == _StepState.pending
                      ? OnlineColors.textDim
                      : OnlineColors.textPrimary,
                ),
              ),
              if (state == _StepState.active) ...[
                const SizedBox(height: 2),
                Text(
                  'In Bearbeitung…',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: OnlineColors.primary,
                  ),
                ),
              ],
              if (!isLast) const SizedBox(height: 36),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pulsing icon for active step
// ---------------------------------------------------------------------------

class _PulseIcon extends StatefulWidget {
  const _PulseIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Icon(widget.icon, color: widget.color, size: 20),
    );
  }
}
