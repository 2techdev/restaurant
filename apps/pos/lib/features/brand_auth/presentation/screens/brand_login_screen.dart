/// Brand login screen — email / password authentication before the PIN screen.
///
/// First screen shown on app launch when no valid session is stored.
/// Matches the Stitch V2 dark design system.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/features/brand_auth/presentation/providers/brand_auth_provider.dart';

class BrandLoginScreen extends ConsumerStatefulWidget {
  const BrandLoginScreen({super.key});

  @override
  ConsumerState<BrandLoginScreen> createState() => _BrandLoginScreenState();
}

class _BrandLoginScreenState extends ConsumerState<BrandLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final success = await ref.read(brandAuthProvider.notifier).login(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
          rememberMe: _rememberMe,
        );
    if (success && mounted) {
      context.go(AppRoutes.login); // → PIN screen
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(brandAuthProvider);
    final isLoading = authState.isLoading;
    final error = authState.error;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: SafeArea(
        child: Row(
          children: [
            // ── Left decorative panel (hidden on small screens) ──────────────
            if (MediaQuery.of(context).size.width > 800)
              _buildLeftPanel(),

            // ── Right / main login form ──────────────────────────────────────
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 48,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo
                        _buildLogo(),
                        const SizedBox(height: 48),

                        // Heading
                        const Text(
                          'Anmelden',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Melden Sie sich mit Ihren Zugangsdaten an.',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Error banner
                        if (error != null) ...[
                          _buildErrorBanner(error),
                          const SizedBox(height: 20),
                        ],

                        // Form
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildLabel('E-Mail'),
                              const SizedBox(height: 8),
                              _buildEmailField(),
                              const SizedBox(height: 20),
                              _buildLabel('Passwort'),
                              const SizedBox(height: 8),
                              _buildPasswordField(),
                              const SizedBox(height: 16),

                              // Remember me + forgot password
                              Row(
                                children: [
                                  _buildRememberMeToggle(),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () =>
                                        context.go(AppRoutes.forgotPassword),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                      padding: EdgeInsets.zero,
                                    ),
                                    child: const Text(
                                      'Passwort vergessen?',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 32),

                              // Login button
                              _buildLoginButton(isLoading),
                              const SizedBox(height: 24),

                              // Register link
                              _buildRegisterLink(),
                            ],
                          ),
                        ),

                        const SizedBox(height: 48),
                        _buildFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Left decorative panel
  // ---------------------------------------------------------------------------

  Widget _buildLeftPanel() {
    return Container(
      width: 420,
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(64),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            // Gradient accent bar
            Container(
              height: 4,
              width: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(
                  colors: [Color(0xFF90ABFF), Color(0xFF316BF3)],
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Restaurant-\nManagement\nder nächsten\nGeneration.',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.2,
                letterSpacing: -1.0,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Bestell-, Tisch- und Zahlungsmanagement '
              'in einer einzigen, blitzschnellen App.',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
            const Spacer(),
            // Feature bullets
            _buildBullet(Icons.bolt_rounded, 'Echtzeit-Synchronisation'),
            const SizedBox(height: 16),
            _buildBullet(Icons.wifi_off_rounded, 'Offline-Modus'),
            const SizedBox(height: 16),
            _buildBullet(Icons.storefront_rounded, 'Online-Bestellungen'),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildBullet(IconData icon, String label) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.accentDim,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 16),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Logo
  // ---------------------------------------------------------------------------

  Widget _buildLogo() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              colors: [Color(0xFF90ABFF), Color(0xFF316BF3)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(
            Icons.restaurant_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF90ABFF), Color(0xFF316BF3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'GASTROCORE',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 3.0,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Form fields
  // ---------------------------------------------------------------------------

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 15,
      ),
      decoration: _inputDecoration(
        hint: 'name@restaurant.ch',
        prefixIcon: Icons.mail_outline_rounded,
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'E-Mail ist erforderlich';
        if (!v.contains('@')) return 'Ungültige E-Mail-Adresse';
        return null;
      },
      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordCtrl,
      obscureText: _obscurePassword,
      autofillHints: const [AutofillHints.password],
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 15,
      ),
      decoration: _inputDecoration(
        hint: '••••••••',
        prefixIcon: Icons.lock_outline_rounded,
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: AppColors.textDim,
            size: 20,
          ),
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Passwort ist erforderlich';
        return null;
      },
      onFieldSubmitted: (_) => _onLogin(),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: AppColors.textDim,
        fontSize: 15,
      ),
      filled: true,
      fillColor: AppColors.bgInput,
      prefixIcon: Icon(prefixIcon, color: AppColors.textDim, size: 20),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: AppColors.borderFocused,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
      errorStyle: const TextStyle(color: AppColors.red, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Remember me toggle
  // ---------------------------------------------------------------------------

  Widget _buildRememberMeToggle() {
    return GestureDetector(
      onTap: () => setState(() => _rememberMe = !_rememberMe),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: _rememberMe
                  ? const Color(0xFF316BF3)
                  : AppColors.surfaceContainerHigh,
            ),
            child: _rememberMe
                ? const Icon(
                    Icons.check_rounded,
                    size: 13,
                    color: Colors.white,
                  )
                : null,
          ),
          const SizedBox(width: 10),
          const Text(
            'Angemeldet bleiben',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Buttons
  // ---------------------------------------------------------------------------

  Widget _buildLoginButton(bool isLoading) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : _onLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF316BF3),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF316BF3).withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Anmelden',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }

  Widget _buildRegisterLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Noch kein Konto? ',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        GestureDetector(
          onTap: () => context.go(AppRoutes.register),
          child: const Text(
            'Kostenlos registrieren',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF90ABFF),
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFF90ABFF),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Error banner
  // ---------------------------------------------------------------------------

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.redDim,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.red, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Footer
  // ---------------------------------------------------------------------------

  Widget _buildFooter() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'GastroCore v1.0.0',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textDim,
            letterSpacing: 1.0,
          ),
        ),
        SizedBox(width: 12),
        _FooterDot(),
        SizedBox(width: 12),
        Text(
          '© 2025 2Tech',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textDim,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}

class _FooterDot extends StatelessWidget {
  const _FooterDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.textDim,
      ),
    );
  }
}
