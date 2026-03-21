/// Kiosk welcome / attract screen.
///
/// Displayed when the kiosk is idle. Shows a full-screen branded
/// background with an animated "Order Here / Bestellen" call-to-action
/// and a language selector in the top-right corner.
///
/// Tapping the CTA or anywhere on the main area navigates to the
/// language selection screen if the locale has not yet been chosen,
/// otherwise directly to the menu.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/features/kiosk/presentation/providers/kiosk_provider.dart';
import 'package:gastrocore_pos/features/kiosk/router/kiosk_router.dart';
import 'package:gastrocore_pos/features/kiosk/theme/kiosk_theme.dart';

class KioskWelcomeScreen extends ConsumerStatefulWidget {
  const KioskWelcomeScreen({super.key});

  @override
  ConsumerState<KioskWelcomeScreen> createState() => _KioskWelcomeScreenState();
}

class _KioskWelcomeScreenState extends ConsumerState<KioskWelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Cycling attract-mode text in 4 Swiss languages.
  static const _attractTexts = [
    'Order Here',
    'Hier bestellen',
    'Commander ici',
    'Ordinare qui',
  ];
  int _attractIndex = 0;
  Timer? _attractTimer;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _attractTimer =
        Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        setState(() {
          _attractIndex = (_attractIndex + 1) % _attractTexts.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _attractTimer?.cancel();
    super.dispose();
  }

  void _onTap() => context.go(KioskRoutes.language);

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(kioskLocaleProvider);

    return Scaffold(
      body: GestureDetector(
        onTap: _onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Gradient background (food-warm) ────────────────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1A0A00),
                    Color(0xFF3D1500),
                    Color(0xFF6B2800),
                  ],
                ),
              ),
            ),

            // Decorative radial glow (simulated food-photography warm light)
            Center(
              child: Container(
                width: 700,
                height: 700,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      KioskColors.primary.withOpacity(0.25),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── Language selector — top right ──────────────────────────────
            Positioned(
              top: 24,
              right: 24,
              child: _LanguagePillRow(currentLocale: locale),
            ),

            // ── Centre content ─────────────────────────────────────────────
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Brand wordmark
                Text(
                  'GastroCore',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: KioskColors.primary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                ),
                const SizedBox(height: 40),

                // Animated CTA
                ScaleTransition(
                  scale: _pulseAnim,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 64,
                      vertical: 32,
                    ),
                    decoration: BoxDecoration(
                      color: KioskColors.primary,
                      borderRadius:
                          BorderRadius.circular(kKioskRadiusXL),
                      boxShadow: [
                        BoxShadow(
                          color: KioskColors.primary.withOpacity(0.5),
                          blurRadius: 40,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.touch_app_rounded,
                          color: Colors.white,
                          size: 56,
                        ),
                        const SizedBox(height: 16),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.3),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: Text(
                            _attractTexts[_attractIndex],
                            key: ValueKey(_attractIndex),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 48),

                Text(
                  'Tap to start your order',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 18,
                  ),
                ),
              ],
            ),

            // ── Step indicator ─────────────────────────────────────────────
            const Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: _StepIndicator(currentStep: 0),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Language pill row (top-right compact selector)
// ---------------------------------------------------------------------------

class _LanguagePillRow extends ConsumerWidget {
  final Locale currentLocale;
  const _LanguagePillRow({required this.currentLocale});

  static const _langs = [
    ('DE', Locale('de')),
    ('FR', Locale('fr')),
    ('IT', Locale('it')),
    ('EN', Locale('en')),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: _langs.map((entry) {
        final (code, locale) = entry;
        final isActive = currentLocale.languageCode == locale.languageCode;
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: GestureDetector(
            onTap: () => ref.read(kioskLocaleProvider.notifier).state = locale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? KioskColors.primary
                    : Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(kKioskRadiusSmall),
              ),
              child: Text(
                code,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight:
                      isActive ? FontWeight.w700 : FontWeight.w400,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Step progress indicator (shared across kiosk screens)
// ---------------------------------------------------------------------------

class _StepIndicator extends StatelessWidget {
  final int currentStep; // 0-based, max 3
  const _StepIndicator({required this.currentStep});

  static const _labels = ['Language', 'Menu', 'Cart', 'Payment'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_labels.length, (i) {
        final active = i == currentStep;
        final done = i < currentStep;
        return Row(
          children: [
            if (i > 0)
              Container(
                width: 40,
                height: 2,
                color: done
                    ? KioskColors.primary
                    : Colors.white.withOpacity(0.3),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: active ? 32 : 24,
              height: active ? 32 : 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? KioskColors.primary
                    : done
                        ? KioskColors.primaryLight
                        : Colors.white.withOpacity(0.2),
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: active ? 14 : 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// Exported so other kiosk screens can use the same step indicator.
class KioskStepIndicator extends StatelessWidget {
  final int currentStep;
  const KioskStepIndicator({super.key, required this.currentStep});

  @override
  Widget build(BuildContext context) => _StepIndicator(currentStep: currentStep);
}
