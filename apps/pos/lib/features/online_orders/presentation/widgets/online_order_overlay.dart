/// Overlay notification for incoming online orders.
///
/// Sits inside a [Stack] on the order-centre shell. When a new online order
/// arrives it slides in from the bottom-right corner, showing the order
/// summary and two action buttons: "Annehmen" (Accept) and "Ablehnen" (Reject).
///
/// After all pending orders are resolved the overlay disappears automatically.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/online_orders/domain/models/online_order_message.dart';
import 'package:gastrocore_pos/features/online_orders/presentation/providers/online_order_provider.dart';

// ---------------------------------------------------------------------------
// Online Order Overlay — main entry point
// ---------------------------------------------------------------------------

/// Renders a slide-in card for the first pending online order.
///
/// Wrap your screen body in a [Stack] and place this widget as the last
/// child so it floats above all content.
class OnlineOrderOverlay extends ConsumerWidget {
  const OnlineOrderOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(pendingOnlineOrdersProvider);
    if (orders.isEmpty) return const SizedBox.shrink();

    return Positioned(
      right: 20,
      bottom: 24,
      width: 340,
      child: _OnlineOrderCard(order: orders.first),
    );
  }
}

// ---------------------------------------------------------------------------
// Single order card
// ---------------------------------------------------------------------------

class _OnlineOrderCard extends ConsumerStatefulWidget {
  final OnlineOrderPayload order;
  const _OnlineOrderCard({required this.order});

  @override
  ConsumerState<_OnlineOrderCard> createState() => _OnlineOrderCardState();
}

class _OnlineOrderCardState extends ConsumerState<_OnlineOrderCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    );
    _slide = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1).animate(_ctrl);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _formatCHF(int cents) {
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    return 'CHF $whole.$frac';
  }

  Future<void> _accept() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    await _ctrl.reverse();
    await acceptOnlineOrder(ref, widget.order.id);
  }

  Future<void> _reject() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    await _ctrl.reverse();
    await rejectOnlineOrder(ref, widget.order.id, 'rejected by staff');
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final customerLabel = order.customerName?.isNotEmpty == true
        ? order.customerName!
        : 'Gast';

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- Header ---
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(13)),
                ),
                child: Row(
                  children: [
                    // Pulsing ONLINE badge
                    _PulsingBadge(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Neue Online-Bestellung #${order.orderNumber}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            customerLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _formatCHF(order.total),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),

              // --- Items list ---
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in order.items.take(4))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          children: [
                            Text(
                              '${item.quantity}×',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.productName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (order.items.length > 4)
                      Text(
                        '+ ${order.items.length - 4} weitere Positionen',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textDim,
                        ),
                      ),
                    if (order.notes?.isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.sticky_note_2_outlined,
                              size: 12, color: AppColors.yellow),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              order.notes!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.yellow,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // --- Action buttons ---
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    // Reject
                    Expanded(
                      child: _ActionButton(
                        label: 'Ablehnen',
                        color: AppColors.red,
                        icon: Icons.close_rounded,
                        isLoading: _isProcessing,
                        onTap: _reject,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Accept
                    Expanded(
                      flex: 2,
                      child: _ActionButton(
                        label: 'Annehmen',
                        color: AppColors.green,
                        icon: Icons.check_rounded,
                        isLoading: _isProcessing,
                        onTap: _accept,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pulsing ONLINE badge
// ---------------------------------------------------------------------------

class _PulsingBadge extends StatefulWidget {
  @override
  State<_PulsingBadge> createState() => _PulsingBadgeState();
}

class _PulsingBadgeState extends State<_PulsingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.92, end: 1.08)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'ONLINE',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.accent,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action button
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool isLoading;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
