/// Splash screen for GastroCore POS.
///
/// Shows an animated logo on first render while the app boots. After a brief
/// animation sequence the screen navigates to the onboarding wizard (first
/// launch) or directly to the PIN login screen (returning users).
/// The first-launch flag is stored as `onboarding_complete` in
/// [SharedPreferences].
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/router/app_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Logo fade + scale
  late final AnimationController _logoController;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;

  // Tagline fade (slightly delayed)
  late final AnimationController _taglineController;
  late final Animation<double> _taglineFade;

  // Pulse ring around the logo mark
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();

    // -- Logo animation -------------------------------------------------------
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _logoFade = CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOut,
    );
    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );

    // -- Tagline animation ----------------------------------------------------
    _taglineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _taglineFade = CurvedAnimation(
      parent: _taglineController,
      curve: Curves.easeOut,
    );

    // -- Pulse ring animation -------------------------------------------------
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _pulseScale = Tween<double>(begin: 1.0, end: 1.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.4, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    _runAnimationSequence();
  }

  Future<void> _runAnimationSequence() async {
    // Small initial delay so the scaffold renders first
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _logoController.forward();

    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _taglineController.forward();

    // Hold the splash for a beat before navigating
    await Future<void>.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_complete') ?? false;

    if (!mounted) return;
    if (onboardingDone) {
      context.go(AppRoutes.login);
    } else {
      context.go(AppRoutes.onboarding);
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _taglineController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Semantics(
        label: 'GastroCore POS yükleniyor',
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Logo mark with pulse ring ─────────────────────────────────
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Pulse ring
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, _) {
                        return Transform.scale(
                          scale: _pulseScale.value,
                          child: Opacity(
                            opacity: _pulseOpacity.value,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.accent,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // Logo
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: _GastroCoreLogo(size: 72),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── App name ─────────────────────────────────────────────────
              FadeTransition(
                opacity: _logoFade,
                child: const Text(
                  'GastroCore',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // ── Tagline ──────────────────────────────────────────────────
              FadeTransition(
                opacity: _taglineFade,
                child: const Text(
                  'Precision POS Framework',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textDim,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              const SizedBox(height: 60),

              // ── Progress indicator ───────────────────────────────────────
              FadeTransition(
                opacity: _taglineFade,
                child: SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    backgroundColor: AppColors.surfaceContainerHigh,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.accent,
                    ),
                    minHeight: 2,
                    borderRadius: BorderRadius.circular(2),
                  ),
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
// GastroCore logo mark
// ---------------------------------------------------------------------------

/// A geometric "G" mark rendered purely with Flutter primitives.
/// No external assets required — safe for all build environments.
class _GastroCoreLogo extends StatelessWidget {
  const _GastroCoreLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryContainer],
        ),
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            fontSize: size * 0.52,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -1,
          ),
        ),
      ),
    );
  }
}
