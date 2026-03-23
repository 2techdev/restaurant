/// Kiosk order confirmation screen.
///
/// Displays the assigned order number prominently after a successful order
/// submission. Auto-returns to the welcome screen after 10 seconds and
/// resets the session. The customer can also tap "New Order" to return
/// immediately.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/features/kiosk/presentation/providers/kiosk_provider.dart';
import 'package:gastrocore_pos/features/kiosk/router/kiosk_router.dart';
import 'package:gastrocore_pos/features/kiosk/theme/kiosk_theme.dart';

/// Duration before auto-returning to the welcome screen.
const _kConfirmationAutoReturn = Duration(seconds: 10);

class KioskConfirmationScreen extends ConsumerStatefulWidget {
  const KioskConfirmationScreen({super.key});

  @override
  ConsumerState<KioskConfirmationScreen> createState() =>
      _KioskConfirmationScreenState();
}

class _KioskConfirmationScreenState
    extends ConsumerState<KioskConfirmationScreen>
    with SingleTickerProviderStateMixin {
  Timer? _autoReturnTimer;
  int _secondsRemaining = _kConfirmationAutoReturn.inSeconds;

  late final AnimationController _checkCtrl;
  late final Animation<double> _checkScale;
  late final Animation<double> _checkOpacity;

  @override
  void initState() {
    super.initState();

    // Entrance animation for the checkmark.
    _checkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _checkScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _checkCtrl,
        curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
      ),
    );
    _checkOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _checkCtrl,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );

    // Start countdown for auto-return.
    _autoReturnTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsRemaining--);
      if (_secondsRemaining <= 0) {
        t.cancel();
        _goHome();
      }
    });
  }

  @override
  void dispose() {
    _autoReturnTimer?.cancel();
    _checkCtrl.dispose();
    super.dispose();
  }

  void _goHome() {
    ref.read(kioskSessionProvider.notifier).reset();
    if (mounted) context.go(KioskRoutes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(kioskSessionProvider);
    final orderNumber = session.confirmedOrderNumber ?? '----';

    return Scaffold(
      backgroundColor: KioskColors.bgPage,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Decorative gradient background ─────────────────────────────
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.2,
                  colors: [
                    KioskColors.successContainer,
                    KioskColors.bgPage,
                  ],
                ),
              ),
            ),

            // ── Main content ───────────────────────────────────────────────
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated checkmark
                  FadeTransition(
                    opacity: _checkOpacity,
                    child: ScaleTransition(
                      scale: _checkScale,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KioskColors.success,
                          boxShadow: [
                            BoxShadow(
                              color: KioskColors.success.withValues(alpha: 0.4),
                              blurRadius: 40,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 64,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  Text(
                    'Order Placed!',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: KioskColors.textPrimary,
                        ),
                  ),

                  const SizedBox(height: 16),
                  Text(
                    'Your order has been sent to the kitchen.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: KioskColors.textSecondary,
                        ),
                  ),

                  const SizedBox(height: 48),

                  // Order number chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: KioskColors.bgCard,
                      borderRadius:
                          BorderRadius.circular(kKioskRadiusXL),
                      border: Border.all(
                        color: KioskColors.border,
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 24,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Your order number',
                          style: TextStyle(
                            fontSize: 16,
                            color: KioskColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '#$orderNumber',
                          style: const TextStyle(
                            fontSize: 72,
                            fontWeight: FontWeight.w900,
                            color: KioskColors.primary,
                            letterSpacing: -2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // "New Order" button
                  ElevatedButton(
                    onPressed: _goHome,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 18,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.home_rounded, size: 22),
                        SizedBox(width: 12),
                        Text('New Order', style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Countdown indicator
                  _CountdownBar(
                    totalSeconds:
                        _kConfirmationAutoReturn.inSeconds,
                    secondsRemaining: _secondsRemaining,
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Returning to home in $_secondsRemaining second'
                    '${_secondsRemaining == 1 ? '' : 's'}…',
                    style: const TextStyle(
                      fontSize: 14,
                      color: KioskColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Countdown progress bar
// ---------------------------------------------------------------------------

class _CountdownBar extends StatelessWidget {
  final int totalSeconds;
  final int secondsRemaining;

  const _CountdownBar({
    required this.totalSeconds,
    required this.secondsRemaining,
  });

  @override
  Widget build(BuildContext context) {
    final progress = secondsRemaining / totalSeconds;
    return SizedBox(
      width: 280,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          backgroundColor: KioskColors.border,
          valueColor: const AlwaysStoppedAnimation<Color>(KioskColors.primary),
        ),
      ),
    );
  }
}
