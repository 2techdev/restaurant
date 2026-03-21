/// Customer-facing Order Display Screen.
///
/// Full-screen landscape layout split into two panels:
///   LEFT  — "Preparing"  (amber/yellow)  orders being made in the kitchen.
///   RIGHT — "Ready"      (green, pulsing) orders ready for pickup.
///
/// Tap the settings icon (3-second long-press to avoid accidental navigation)
/// to open [OdsSettingsScreen].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/features/ods/presentation/providers/ods_provider.dart';
import 'package:gastrocore_pos/features/ods/router/ods_router.dart';
import 'package:gastrocore_pos/features/ods/theme/ods_theme.dart';

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

class OdsMainScreen extends ConsumerWidget {
  const OdsMainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final odsState = ref.watch(odsProvider);
    final restaurantName = ref.watch(odsRestaurantNameProvider);

    return Scaffold(
      backgroundColor: OdsColors.bgPage,
      body: Column(
        children: [
          _OdsHeader(restaurantName: restaurantName),
          Expanded(
            child: Row(
              children: [
                // ── LEFT: Preparing ────────────────────────────────────────
                Expanded(
                  child: _OrderPanel(
                    title: 'PREPARING',
                    titleColor: OdsColors.preparing,
                    bgColor: OdsColors.preparingBg,
                    orders: odsState.preparing,
                    isReady: false,
                  ),
                ),
                // Divider
                Container(
                  width: 2,
                  color: OdsColors.divider,
                ),
                // ── RIGHT: Ready ───────────────────────────────────────────
                Expanded(
                  child: _OrderPanel(
                    title: 'READY FOR PICKUP',
                    titleColor: OdsColors.ready,
                    bgColor: OdsColors.readyBg,
                    orders: odsState.ready,
                    isReady: true,
                  ),
                ),
              ],
            ),
          ),
          _OdsFooter(isConnected: odsState.isConnected),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header bar
// ---------------------------------------------------------------------------

class _OdsHeader extends ConsumerWidget {
  const _OdsHeader({required this.restaurantName});

  final String restaurantName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 72,
      color: OdsColors.bgHeader,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Restaurant name
          Text(
            restaurantName,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: OdsColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          // Live clock
          _LiveClock(),
          const SizedBox(width: 16),
          // Settings — long-press to avoid accidental taps
          GestureDetector(
            onLongPress: () => context.push(OdsRoutes.settings),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: OdsColors.bgCardAlt,
                borderRadius: BorderRadius.circular(kOdsRadiusSmall),
              ),
              child: const Icon(
                Icons.settings,
                color: OdsColors.textDim,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live clock
// ---------------------------------------------------------------------------

class _LiveClock extends StatefulWidget {
  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late DateTime _now;
  late final _ticker = Stream.periodic(const Duration(seconds: 1));
  late final _sub = _ticker.listen((_) {
    if (mounted) setState(() => _now = DateTime.now());
  });

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    return Text(
      '$h:$m',
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: OdsColors.textSecondary,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Order panel (left or right half)
// ---------------------------------------------------------------------------

class _OrderPanel extends StatelessWidget {
  const _OrderPanel({
    required this.title,
    required this.titleColor,
    required this.bgColor,
    required this.orders,
    required this.isReady,
  });

  final String title;
  final Color titleColor;
  final Color bgColor;
  final List<OdsOrder> orders;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bgColor,
      child: Column(
        children: [
          // Section header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: titleColor.withValues(alpha: 0.12),
              border: Border(
                bottom: BorderSide(
                  color: titleColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isReady ? Icons.check_circle_rounded : Icons.restaurant,
                  color: titleColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                // Order count badge
                if (orders.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: titleColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${orders.length}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: titleColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Order grid
          Expanded(
            child: orders.isEmpty
                ? _EmptyPanel(isReady: isReady, titleColor: titleColor)
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return isReady
                          ? _ReadyOrderCard(order: order)
                          : _PreparingOrderCard(order: order);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state for a panel
// ---------------------------------------------------------------------------

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.isReady, required this.titleColor});

  final bool isReady;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isReady ? Icons.check_circle_outline : Icons.hourglass_empty,
            size: 64,
            color: titleColor.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            isReady ? 'No orders ready' : 'No orders preparing',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: titleColor.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preparing order card (static)
// ---------------------------------------------------------------------------

class _PreparingOrderCard extends StatelessWidget {
  const _PreparingOrderCard({required this.order});

  final OdsOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: OdsColors.preparingCardBg,
        borderRadius: BorderRadius.circular(kOdsRadiusMedium),
        border: Border.all(
          color: OdsColors.preparingBorder,
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Order number — dominant display
          Text(
            order.formattedNumber,
            style: const TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w900,
              color: OdsColors.preparing,
              letterSpacing: -1.0,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          _ChannelChip(channel: order.channel, isReady: false),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ready order card (pulsing animation)
// ---------------------------------------------------------------------------

class _ReadyOrderCard extends StatefulWidget {
  const _ReadyOrderCard({required this.order});

  final OdsOrder order;

  @override
  State<_ReadyOrderCard> createState() => _ReadyOrderCardState();
}

class _ReadyOrderCardState extends State<_ReadyOrderCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: OdsColors.readyCardBg,
            borderRadius: BorderRadius.circular(kOdsRadiusMedium),
            border: Border.all(
              color: OdsColors.ready.withValues(alpha: _pulse.value),
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: OdsColors.ready.withValues(alpha: _pulse.value * 0.25),
                blurRadius: 16 * _pulse.value,
                spreadRadius: 2 * _pulse.value,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Order number
          Text(
            widget.order.formattedNumber,
            style: const TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w900,
              color: OdsColors.ready,
              letterSpacing: -1.0,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          _ChannelChip(channel: widget.order.channel, isReady: true),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Source channel chip
// ---------------------------------------------------------------------------

class _ChannelChip extends StatelessWidget {
  const _ChannelChip({required this.channel, required this.isReady});

  final String channel;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = _channelInfo(channel);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  (IconData, String, Color) _channelInfo(String ch) => switch (ch) {
        'kiosk' => (
            Icons.tablet_android,
            'KIOSK',
            OdsColors.sourceKiosk,
          ),
        'web' || 'online' => (
            Icons.public,
            'ONLINE',
            OdsColors.sourceOnline,
          ),
        'qr' => (
            Icons.qr_code,
            'QR',
            OdsColors.sourceOnline,
          ),
        'waiter' => (
            Icons.person,
            'WAITER',
            OdsColors.sourceCounter,
          ),
        _ => (
            Icons.point_of_sale,
            'COUNTER',
            OdsColors.sourceCounter,
          ),
      };
}

// ---------------------------------------------------------------------------
// Footer
// ---------------------------------------------------------------------------

class _OdsFooter extends StatelessWidget {
  const _OdsFooter({required this.isConnected});

  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: OdsColors.bgHeader,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Connection status
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isConnected ? OdsColors.ready : const Color(0xFF666666),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'Connected' : 'Offline',
            style: const TextStyle(
              fontSize: 11,
              color: OdsColors.textDim,
            ),
          ),
          const Spacer(),
          // Watermark
          const Text(
            'Powered by GastroCore',
            style: TextStyle(
              fontSize: 11,
              color: OdsColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}
