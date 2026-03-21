/// Order tracking screen — real-time status via polling.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    final trackingAsync =
        ref.watch(orderTrackingProvider(orderId));

    return Scaffold(
      backgroundColor: OnlineColors.bgPage,
      appBar: AppBar(
        title: Text(l10n.orderStatus),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () =>
              context.go('/$restaurantId/menu'),
        ),
      ),
      body: trackingAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: OnlineColors.primary),
        ),
        error: (_, __) => _buildStaticView(context, l10n, null),
        data: (status) => _buildStaticView(context, l10n, status),
      ),
    );
  }

  Widget _buildStaticView(
    BuildContext context,
    AppLocalizations l10n,
    OrderStatusResponse? status,
  ) {
    final currentStatus =
        status?.status ?? OrderStatus.received;

    final steps = [
      _TrackingStep(
        status: OrderStatus.received,
        label: l10n.statusReceived,
        icon: Icons.receipt_long,
      ),
      _TrackingStep(
        status: OrderStatus.preparing,
        label: l10n.statusPreparing,
        icon: Icons.local_fire_department,
      ),
      _TrackingStep(
        status: OrderStatus.ready,
        label: l10n.statusReady,
        icon: Icons.check_circle_outline,
      ),
      _TrackingStep(
        status: OrderStatus.served,
        label: l10n.statusServed,
        icon: Icons.restaurant,
      ),
    ];

    final currentIdx = _statusIndex(currentStatus);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Order number
          if (status != null) ...[
            Text(
              l10n.orderNumber('${status.orderNumber}'),
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: OnlineColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.estimatedWait(
                  '${status.estimatedWaitMinutes}'),
              style: const TextStyle(
                color: OnlineColors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 40),
          ],

          // Status steps
          ...steps.asMap().entries.map((entry) {
            final idx = entry.key;
            final step = entry.value;
            final stepState = _getStepState(idx, currentIdx);
            return _TrackingStepWidget(
              step: step,
              state: stepState,
              isLast: idx == steps.length - 1,
            );
          }),

          const SizedBox(height: 40),

          // Back to menu
          OutlinedButton.icon(
            onPressed: () => context.go('/$restaurantId/menu'),
            icon: const Icon(Icons.restaurant_menu),
            label: Text(l10n.backToMenu),
          ),

          const SizedBox(height: 16),

          // Polling indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: OnlineColors.textDim,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Updating every 10 seconds…',
                style: const TextStyle(
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

  _StepState _getStepState(int stepIdx, int currentIdx) {
    if (stepIdx < currentIdx) return _StepState.done;
    if (stepIdx == currentIdx) return _StepState.active;
    return _StepState.pending;
  }
}

// ---------------------------------------------------------------------------
// Step model & state
// ---------------------------------------------------------------------------

enum _StepState { done, active, pending }

class _TrackingStep {
  const _TrackingStep({
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

class _TrackingStepWidget extends StatelessWidget {
  const _TrackingStepWidget({
    required this.step,
    required this.state,
    required this.isLast,
  });

  final _TrackingStep step;
  final _StepState state;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    Color iconColor;
    Color bgColor;
    Color lineColor;
    FontWeight fontWeight;

    switch (state) {
      case _StepState.done:
        iconColor = Colors.white;
        bgColor = OnlineColors.green;
        lineColor = OnlineColors.green;
        fontWeight = FontWeight.w400;
      case _StepState.active:
        iconColor = Colors.white;
        bgColor = OnlineColors.primary;
        lineColor = OnlineColors.divider;
        fontWeight = FontWeight.w700;
      case _StepState.pending:
        iconColor = OnlineColors.textDim;
        bgColor = OnlineColors.chipBg;
        lineColor = OnlineColors.divider;
        fontWeight = FontWeight.w400;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon + connector
        Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: state == _StepState.active
                  ? _PulsingIcon(icon: step.icon, color: iconColor)
                  : Icon(step.icon, color: iconColor, size: 22),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: lineColor,
              ),
          ],
        ),
        const SizedBox(width: 16),

        // Label
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            step.label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: fontWeight,
              color: state == _StepState.pending
                  ? OnlineColors.textSecondary
                  : OnlineColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pulsing icon for active step
// ---------------------------------------------------------------------------

class _PulsingIcon extends StatefulWidget {
  const _PulsingIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
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
    _anim = Tween<double>(begin: 0.7, end: 1.0).animate(
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
      child: Icon(widget.icon, color: widget.color, size: 22),
    );
  }
}
